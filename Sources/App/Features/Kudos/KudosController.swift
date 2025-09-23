//
//  KudosController.swift
//  kudos-vapor
//
//  Логика бота (обработка команд) + TelegramService (поллинг и отправка сообщений).
//

import Vapor
import Fluent
import Foundation
import NIOCore

// MARK: - Бизнес-логика бота

enum BotController {
    /// Обработка одного входящего сообщения Telegram
    static func handle(app: Application, message m: TgMessage, api: String, sessions: SessionStore) async {
        let chat = m.chat.id
        let text = (m.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Базовые команды
        switch true {
        case text == "/start":
            await TelegramService.sendMessage(app, api: api, chatId: chat,
                                              text: "Привет! Команды:\n/thanks — поблагодарить коллегу\n/export — выгрузка CSV")
            return

        case text == "/export":
            do {
                // Экспортируем все записи в CSV и отправляем одним файлом
                let path = "kudos_export.csv"
                try await CSVExporter.exportKudos(db: app.db, to: path)
                try await TelegramService.sendDocument(app, api: api, chatId: chat, filePath: path, caption: "Экспорт благодарностей")
            } catch {
                await TelegramService.sendMessage(app, api: api, chatId: chat, text: "Экспорт не удался: \(error.localizedDescription)")
            }
            return

        case text == "/thanks":
            // Запускаем пошаговый сценарий: сначала ждём @username, затем причину
            await sessions.set(chat, Session(to: nil))
            await TelegramService.sendMessage(app, api: api, chatId: chat,
                                              text: "Кому сказать спасибо? Пришли @username, затем одним сообщением причину (≥ 20 символов).")
            return

        default:
            break
        }

        // Пошаговый сценарий: 1) пользователь присылает @username
        if text.hasPrefix("@") {
            if var s = await sessions.get(chat), s.to == nil {
                s.to = text
                await sessions.set(chat, s)
                await TelegramService.sendMessage(app, api: api, chatId: chat,
                                                  text: "Ок, \(text). Теперь пришли причину (≥ 20 символов).")
                return
            }
        }

        // Пошаговый сценарий: 2) если username уже известен, и текст достаточно длинный — записываем спасибо
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
                await sessions.set(chat, nil) // очищаем сессию
                await TelegramService.sendMessage(app, api: api, chatId: chat, text: "Готово! Записал спасибо для \(to).")
            } catch {
                await TelegramService.sendMessage(app, api: api, chatId: chat, text: "Ошибка записи: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Telegram API helper

public enum TelegramService {
    /// Бесконечный поллинг Telegram getUpdates (long polling)
    public static func poll(app: Application, sessions: SessionStore) async {
        guard let token = Environment.get("BOT_TOKEN") else {
            app.logger.critical("BOT_TOKEN is not set")
            return
        }
        let api = "https://api.telegram.org/bot\(token)"
        var offset = 0

        while !Task.isCancelled {
            do {
                var url = URI(string: "\(api)/getUpdates")
                url.query = "timeout=25&offset=\(offset)&allowed_updates=%5B%22message%22%5D"

                let res = try await app.client.get(url)
                let payload = try res.content.decode(TgResp<[TgUpdate]>.self)

                // Обрабатываем новые апдейты
                for u in payload.result {
                    offset = u.update_id + 1
                    if let m = u.message {
                        await BotController.handle(app: app, message: m, api: api, sessions: sessions)
                    }
                }
            } catch {
                app.logger.report(error: error)
                // Небольшая задержка, чтобы не крутить цикл при ошибке сети/Telegram
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Отправка текстового сообщения
    public static func sendMessage(_ app: Application, api: String, chatId: Int64, text: String) async {
        _ = try? await app.client.post("\(api)/sendMessage") { req in
            try req.content.encode(
                ["chat_id": "\(chatId)", "text": text, "parse_mode": "HTML"],
                as: .json
            )
        }
    }

    /// Отправка CSV-файла как документа
    public static func sendDocument(_ app: Application, api: String, chatId: Int64, filePath: String, caption: String?) async throws {
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
