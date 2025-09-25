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
        let chatId = m.chat.id
        let text = (m.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) /start → показываем главное меню
        if text == "/start" {
            await BotMenuController.handleStart(app: app, api: api, chatId: chatId, sessions: sessions)
            return
        }

        // 2) Весь остальной текст → отдаём в BotMenu (главное меню, подменю, шаги сценария)
        await BotMenuController.handleText(
            app: app,
            api: api,
            chatId: chatId,
            username: m.from?.username,
            text: text,
            sessions: sessions,
            db: app.db
        )
        return
    }
}

// MARK: - Telegram API helper

public enum TelegramService {
    
    // Запуск цикла опроса Telegram API
    /**
     Запускает бесконечный цикл опроса Telegram API (`getUpdates`).

     - Параметры:
       - app: текущее приложение Vapor
       - sessions: хранилище сессий пользователей

     - Что делает:
       - забирает новые апдейты из Telegram
       - передаёт их в `BotController.handle`
       - при ошибке сети делает паузу и пробует снова
     */
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


    
    // Структура полезной нагрузки для Telegram API sendMessage
    /**
     Эта структура описывает JSON, который Telegram ожидает
     при вызове метода `sendMessage`.

     - Параметры:
       - chat_id: идентификатор чата (Int64), куда отправляем сообщение
       - text: сам текст сообщения
       - parse_mode: режим форматирования текста ("HTML", "Markdown" или nil)
       - reply_markup: объект клавиатуры (опционально), чтобы показать кнопки
     */
    private struct SendMessagePayload: Content {
        let chat_id: Int64
        let text: String
        let parse_mode: String?
        let reply_markup: TgReplyKeyboard?
    }

    // Отправка текстового сообщения в чат
    /**
     Метод отправляет текстовое сообщение через Telegram API `sendMessage`.

     - Параметры:
       - app: текущее приложение Vapor
       - api: базовый URL Telegram API (с токеном)
       - chatId: идентификатор чата, куда нужно отправить сообщение
       - text: текст сообщения
       - replyMarkup: (опционально) объект клавиатуры `TgReplyKeyboard`, если нужно показать кнопки

     - Особенности:
       - По умолчанию используется `parse_mode = "HTML"`, чтобы можно было выделять текст жирным, курсивом и вставлять ссылки.
       - Если передан `replyMarkup`, вместе с сообщением отобразится кастомная клавиатура.

     - Примеры:
       ```swift
       // простое сообщение
       await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Привет!")

       // сообщение с клавиатурой
       await TelegramService.sendMessage(
           app,
           api: api,
           chatId: chatId,
           text: "Выберите действие:",
           replyMarkup: KeyboardBuilder.mainMenu()
       )
       ```
    */
    
    static func sendMessage(
        _ app: Application,
        api: String,
        chatId: Int64,
        text: String,
        replyMarkup: TgReplyKeyboard? = nil
    ) async {
        let payload = SendMessagePayload(
            chat_id: chatId,
            text: text,
            parse_mode: "HTML",        // включаем HTML-разметку (жирный, курсив и т.п.)
            reply_markup: replyMarkup  // клавиатура, если она передана
        )
        do {
            _ = try await app.client.post("\(api)/sendMessage") { req in
                try req.content.encode(payload, as: .json) // сериализация в JSON
            }
        } catch {
            app.logger.error("sendMessage failed: \(error.localizedDescription)")
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
