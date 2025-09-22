import Vapor
import Fluent
import FluentSQLiteDriver
import Foundation

// MARK: - Telegram DTO

struct TgResp<T: Decodable>: Decodable { let ok: Bool; let result: T }
struct TgUpdate: Decodable { let update_id: Int; let message: TgMessage? }
struct TgMessage: Decodable { let message_id: Int; let date: Int; let text: String?; let chat: TgChat; let from: TgUser? }
struct TgChat: Decodable { let id: Int64 }
struct TgUser: Decodable { let id: Int64; let username: String?; let first_name: String?; let last_name: String? }

// MARK: - Session Store (потокобезопасно)

actor SessionStore {
    private var sessions: [Int64: Session] = [:]
    func get(_ chatId: Int64) -> Session? { sessions[chatId] }
    func set(_ chatId: Int64, _ s: Session?) { sessions[chatId] = s }
}

struct Session { var to: String? }

// MARK: - App Entry

@available(macOS 12, *)
@main
enum RunApp {
    private static let sessions = SessionStore()

    static func main() async throws {
        // Тонкая точка входа
        let app = try await Application.make(.production)
        defer { app.shutdown() }

        configure(app)
        registerRoutes(app)

        // Long-polling (фоновая таска)
        Task { await TelegramService.poll(app: app, sessions: sessions) }

        try await app.execute()
    }
}

// MARK: - Configuration

private extension RunApp {
    static func configure(_ app: Application) {
        // DB + миграции — оставляем SQLite, позже легко сменить на Postgres
        app.databases.use(.sqlite(.file("kudos.sqlite")), as: .sqlite)
        app.migrations.add(CreateKudos())
        // авто-миграции при старте
        Task { try? await app.autoMigrate() }
    }

    static func registerRoutes(_ app: Application) {
        app.get("health") { _ in "ok" }
    }
}

// MARK: - TelegramService

enum TelegramService {
    static func poll(app: Application, sessions: SessionStore) async {
        guard let token = Environment.get("BOT_TOKEN") else {
            app.logger.critical("BOT_TOKEN is not set"); return
        }
        let api = "https://api.telegram.org/bot\(token)"
        var offset = 0

        while !Task.isCancelled {
            do {
                var url = URI(string: "\(api)/getUpdates")
                url.query = "timeout=25&offset=\(offset)&allowed_updates=%5B%22message%22%5D"
                let res = try await app.client.get(url)
                let payload = try res.content.decode(TgResp<[TgUpdate]>.self)

                for u in payload.result {
                    offset = u.update_id + 1
                    if let m = u.message {
                        await BotController.handle(app: app, message: m, api: api, sessions: sessions)
                    }
                }
            } catch {
                app.logger.report(error: error)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    static func sendMessage(_ app: Application, api: String, chatId: Int64, text: String) async {
        _ = try? await app.client.post("\(api)/sendMessage") { req in
            try req.content.encode(
                ["chat_id": "\(chatId)", "text": text, "parse_mode": "HTML"],
                as: .json
            )
        }
    }

    static func sendDocument(_ app: Application, api: String, chatId: Int64, filePath: String, caption: String?) async throws {
        let url = URI(string: "\(api)/sendDocument")
        var req = ClientRequest(method: .POST, url: url)
        let boundary = "Boundary-\(UUID().uuidString)"
        req.headers.replaceOrAdd(name: .contentType, value: "multipart/form-data; boundary=\(boundary)")

        var body = ByteBufferAllocator().buffer(capacity: 0)

        func addField(_ name: String, _ value: String) {
            body.writeString("--\(boundary)\r\n")
            body.writeString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        func addFile(_ field: String, filename: String, data: Data) {
            body.writeString("--\(boundary)\r\n")
            body.writeString("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n")
            body.writeString("Content-Type: text/csv\r\n\r\n")
            body.writeData(data)
            body.writeString("\r\n")
        }

        addField("chat_id", "\(chatId)")
        if let caption { addField("caption", caption) }

        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        addFile("document", filename: (filePath as NSString).lastPathComponent, data: data)

        body.writeString("--\(boundary)--\r\n")
        req.body = .init(buffer: body)

        _ = try await app.client.send(req)
    }
}

// MARK: - BotController (вся логика команд)

enum BotController {
    static func handle(app: Application, message m: TgMessage, api: String, sessions: SessionStore) async {
        let chat = m.chat.id
        let text = (m.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        switch true {
        case text == "/start":
            await TelegramService.sendMessage(app, api: api, chatId: chat,
                                              text: "Привет! Команды:\n/thanks — поблагодарить коллегу\n/export — выгрузка CSV")
            return

        case text == "/export":
            do {
                let path = "kudos_export.csv"
                try await CSVExporter.exportKudos(db: app.db, to: path)
                try await TelegramService.sendDocument(app, api: api, chatId: chat, filePath: path, caption: "Экспорт благодарностей")
            } catch {
                await TelegramService.sendMessage(app, api: api, chatId: chat, text: "Экспорт не удался: \(error.localizedDescription)")
            }
            return

        case text == "/thanks":
            await sessions.set(chat, Session(to: nil))
            await TelegramService.sendMessage(app, api: api, chatId: chat,
                                              text: "Кому сказать спасибо? Пришли @username, затем одним сообщением причину (≥ 20 символов).")
            return

        default:
            break
        }

        // Пошаговая сессия
        if text.hasPrefix("@") {
            if var s = await sessions.get(chat), s.to == nil {
                s.to = text
                await sessions.set(chat, s)
                await TelegramService.sendMessage(app, api: api, chatId: chat,
                                                  text: "Ок, \(text). Теперь пришли причину (≥ 20 символов).")
                return
            }
        }

        if let s = await sessions.get(chat), let to = s.to, text.count >= 20 {
            let fromUsername = m.from?.username.map { "@\($0)" } ?? "\(m.from?.id ?? 0)"
            let fromName = [m.from?.first_name, m.from?.last_name].compactMap { $0 }.joined(separator: " ")
            let k = Kudos(
                ts: Date(),
                fromUserId: m.from?.id ?? 0,
                fromUsername: fromUsername,
                fromName: fromName.isEmpty ? "—" : fromName,
                toUsername: to,
                reason: text
            )
            do {
                try await k.create(on: app.db)
                await sessions.set(chat, nil)
                await TelegramService.sendMessage(app, api: api, chatId: chat, text: "Готово! Записал спасибо для \(to).")
            } catch {
                await TelegramService.sendMessage(app, api: api, chatId: chat, text: "Ошибка записи: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - CSV Export

enum CSVExporter {
    static func exportKudos(db: Database, to path: String) async throws {
        let rows = try await Kudos.query(on: db).sort(\.$ts, .ascending).all()
        var csv = "Timestamp;From Username;From Name;To Username;Reason\n"
        let df = ISO8601DateFormatter()

        func esc(_ s: String) -> String {
            var v = s.replacingOccurrences(of: "\"", with: "\"\"")
            if v.contains(",") || v.contains("\n") { v = "\"\(v)\"" }
            return v
        }

        for k in rows {
            csv += [
                esc(df.string(from: k.ts)),
                esc(k.fromUsername),
                esc(k.fromName),
                esc(k.toUsername),
                esc(k.reason)
            ].joined(separator: ";") + "\n"
        }

        // BOM для Excel (Windows)
        let final = "\u{FEFF}" + csv
        try final.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}
