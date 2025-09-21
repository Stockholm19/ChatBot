import Vapor
import Fluent
import FluentSQLiteDriver
import Foundation

// Telegram DTO
struct TgResp<T: Decodable>: Decodable { let ok: Bool; let result: T }
struct TgUpdate: Decodable { let update_id: Int; let message: TgMessage? }
struct TgMessage: Decodable { let message_id: Int; let date: Int; let text: String?; let chat: TgChat; let from: TgUser? }
struct TgChat: Decodable { let id: Int64 }
struct TgUser: Decodable { let id: Int64; let username: String?; let first_name: String?; let last_name: String? }

struct Session { var to: String? }

@available(macOS 12, *)
@main
enum RunApp {
    static var sessions = [Int64: Session]()  // chatId -> Session

    static func main() async throws {
        // Новый способ инициализации
        let app = try await Application.make(.production)
        defer { app.shutdown() }

        // БД + миграции
        app.databases.use(.sqlite(.file("kudos.sqlite")), as: .sqlite)
        app.migrations.add(CreateKudos())
        try await app.autoMigrate()

        app.get("health") { _ in "ok" }

        // Long-polling
        Task { await poll(app) }
        try await app.execute()
    }

    static func poll(_ app: Application) async {
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
                    if let m = u.message { await handle(app, m, api: api) }
                }
            } catch {
                app.logger.report(error: error)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    static func send(_ app: Application, api: String, chatId: Int64, text: String) async {
        _ = try? await app.client.post("\(api)/sendMessage") { req in
            try req.content.encode(["chat_id": "\(chatId)", "text": text, "parse_mode": "HTML"], as: .json)
        }
    }

    static func handle(_ app: Application, _ m: TgMessage, api: String) async {
        let chat = m.chat.id
        let text = (m.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if text == "/start" {
            await send(app, api: api, chatId: chat, text: "Привет! Команды:\n/thanks — поблагодарить коллегу\n/export — выгрузка CSV")
            return
        }
        if text == "/export" {
            let path = "kudos_export.csv"
            do { try await exportCSV(db: app.db, to: path); try await sendDocument(app, api: api, chatId: chat, filePath: path, caption: "Экспорт благодарностей") }
            catch { await send(app, api: api, chatId: chat, text: "Экспорт не удался: \(error.localizedDescription)") }
            return
        }
        if text == "/thanks" {
            sessions[chat] = .init(to: nil)
            await send(app, api: api, chatId: chat, text: "Кому сказать спасибо? Пришли @username, затем одним сообщением причину (≥ 20 символов).")
            return
        }
        if var s = sessions[chat], s.to == nil, text.hasPrefix("@") {
            s.to = text; sessions[chat] = s
            await send(app, api: api, chatId: chat, text: "Ок, \(text). Теперь пришли причину (≥ 20 символов).")
            return
        }
        if let s = sessions[chat], let to = s.to, text.count >= 20 {
            let fromUsername = m.from?.username.map { "@\($0)" } ?? "\(m.from?.id ?? 0)"
            let fromName = [m.from?.first_name, m.from?.last_name].compactMap{$0}.joined(separator: " ")
            let k = Kudos(ts: Date(),
                          fromUserId: m.from?.id ?? 0,
                          fromUsername: fromUsername,
                          fromName: fromName.isEmpty ? "—" : fromName,
                          toUsername: to,
                          reason: text)
            do { try await k.create(on: app.db); sessions[chat] = nil; await send(app, api: api, chatId: chat, text: "Готово! Записал спасибо для \(to).") }
            catch { await send(app, api: api, chatId: chat, text: "Ошибка записи: \(error.localizedDescription)") }
            return
        }
    }

static func exportCSV(db: Database, to path: String) async throws {
    let rows = try await Kudos.query(on: db).sort(\.$ts, .ascending).all()
    var csv = "Timestamp;From Username;From Name;To Username;Reason\n"
    let df = ISO8601DateFormatter()
    for k in rows {
        func esc(_ s: String) -> String {
            var v = s.replacingOccurrences(of: "\"", with: "\"\"")
            if v.contains(",") || v.contains("\n") { v = "\"\(v)\"" }
            return v
        }
        csv += [esc(df.string(from: k.ts)),
                esc(k.fromUsername),
                esc(k.fromName),
                esc(k.toUsername),
                esc(k.reason)
        ].joined(separator: ";") + "\n"
    }

    // Добавляем BOM для Excel (Windows)
    let bom = "\u{FEFF}"
    let final = bom + csv

    try final.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
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
            body.writeData(data); body.writeString("\r\n")
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
