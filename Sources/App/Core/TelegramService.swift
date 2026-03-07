//
//  TelegramService.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 25.09.2025.
//

import Vapor
import Foundation
import NIOCore

// DTO одной клавиатуры для всего модуля
public struct TgReplyKeyboard: Content {
    public struct Button: Content { public let text: String }
    public let keyboard: [[Button]]
    public let resize_keyboard: Bool
    public let one_time_keyboard: Bool

    public init(keyboard: [[Button]], resize_keyboard: Bool, one_time_keyboard: Bool) {
        self.keyboard = keyboard
        self.resize_keyboard = resize_keyboard
        self.one_time_keyboard = one_time_keyboard
    }
}

public struct TgInlineKeyboardMarkup: Content {
    public struct Button: Content {
        public let text: String
        public let callback_data: String

        public init(text: String, callback_data: String) {
            self.text = text
            self.callback_data = callback_data
        }
    }

    public let inline_keyboard: [[Button]]

    public init(inline_keyboard: [[Button]]) {
        self.inline_keyboard = inline_keyboard
    }
}

public struct TgReplyKeyboardRemove: Content {
    public let remove_keyboard: Bool

    public init(remove_keyboard: Bool = true) {
        self.remove_keyboard = remove_keyboard
    }
}

public enum TelegramService {

    // MARK: Polling getUpdates
    public static func poll(app: Application, sessions: SessionStore) async {
        guard let token = Environment.get("BOT_TOKEN") else {
            app.logger.critical("BOT_TOKEN is not set")
            await app.pollingHealthStore.markPollError("BOT_TOKEN is not set")
            return
        }
        let api = "https://api.telegram.org/bot\(token)"
        var offset = 0

        while !Task.isCancelled {
            do {
                var url = URI(string: "\(api)/getUpdates")
                url.query = "timeout=25&offset=\(offset)&allowed_updates=%5B%22message%22,%22callback_query%22%5D"

                let res = try await app.client.get(url)
                let payload = try res.content.decode(TgResp<[TgUpdate]>.self)
                await app.pollingHealthStore.markSuccessfulPoll()

                for u in payload.result {
                    offset = u.update_id + 1
                    if let m = u.message {
                        await BotController.handle(app: app, message: m, api: api, sessions: sessions)
                    }
                    if let q = u.callback_query {
                        await BotController.handleCallback(app: app, query: q, api: api, sessions: sessions)
                    }
                }
            } catch {
                app.logger.warning("poll error: \(error.localizedDescription)")
                await app.pollingHealthStore.markPollError(error.localizedDescription)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: sendMessage
    private struct SendMessagePayload: Content {
        let chat_id: Int64
        let text: String
        let parse_mode: String?
        let reply_markup: TgReplyKeyboard?
    }

    private struct SendInlineMessagePayload: Content {
        let chat_id: Int64
        let text: String
        let parse_mode: String?
        let reply_markup: TgInlineKeyboardMarkup
    }

    private struct SendHideKeyboardPayload: Content {
        let chat_id: Int64
        let text: String
        let parse_mode: String?
        let reply_markup: TgReplyKeyboardRemove
    }

    private struct DeleteMessagePayload: Content {
        let chat_id: Int64
        let message_id: Int
    }

    private struct EditMessageTextPayload: Content {
        let chat_id: Int64
        let message_id: Int
        let text: String
        let parse_mode: String?
        let reply_markup: TgInlineKeyboardMarkup?
    }

    private struct EditMessageReplyMarkupPayload: Content {
        let chat_id: Int64
        let message_id: Int
        let reply_markup: TgInlineKeyboardMarkup?
    }

    private struct AnswerCallbackPayload: Content {
        let callback_query_id: String
        let text: String?
        let show_alert: Bool?
    }

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
            parse_mode: "HTML",
            reply_markup: replyMarkup
        )
        do {
            _ = try await app.client.post("\(api)/sendMessage") { req in
                try req.content.encode(payload, as: .json)
            }
        } catch {
            app.logger.error("sendMessage failed: \(error.localizedDescription)")
        }
    }

    static func hideReplyKeyboardSilently(
        _ app: Application,
        api: String,
        chatId: Int64
    ) async {
        let payload = SendHideKeyboardPayload(
            chat_id: chatId,
            text: "…",
            parse_mode: "HTML",
            reply_markup: TgReplyKeyboardRemove()
        )
        do {
            let res = try await app.client.post("\(api)/sendMessage") { req in
                try req.content.encode(payload, as: .json)
            }
            let response = try res.content.decode(TgResp<TgMessage>.self)
            let deletePayload = DeleteMessagePayload(
                chat_id: chatId,
                message_id: response.result.message_id
            )
            _ = try await app.client.post("\(api)/deleteMessage") { req in
                try req.content.encode(deletePayload, as: .json)
            }
        } catch {
            app.logger.error("hideReplyKeyboardSilently failed: \(error.localizedDescription)")
        }
    }

    static func sendMessage(
        _ app: Application,
        api: String,
        chatId: Int64,
        text: String,
        inlineMarkup: TgInlineKeyboardMarkup
    ) async {
        _ = await sendInlineMessage(
            app,
            api: api,
            chatId: chatId,
            text: text,
            inlineMarkup: inlineMarkup
        )
    }

    static func sendInlineMessage(
        _ app: Application,
        api: String,
        chatId: Int64,
        text: String,
        inlineMarkup: TgInlineKeyboardMarkup
    ) async -> Int? {
        let payload = SendInlineMessagePayload(
            chat_id: chatId,
            text: text,
            parse_mode: "HTML",
            reply_markup: inlineMarkup
        )
        do {
            let res = try await app.client.post("\(api)/sendMessage") { req in
                try req.content.encode(payload, as: .json)
            }
            let response = try res.content.decode(TgResp<TgMessage>.self)
            return response.result.message_id
        } catch {
            app.logger.error("sendMessage(inline) failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func editMessageText(
        _ app: Application,
        api: String,
        chatId: Int64,
        messageId: Int,
        text: String,
        inlineMarkup: TgInlineKeyboardMarkup?
    ) async {
        let payload = EditMessageTextPayload(
            chat_id: chatId,
            message_id: messageId,
            text: text,
            parse_mode: "HTML",
            reply_markup: inlineMarkup
        )
        do {
            _ = try await app.client.post("\(api)/editMessageText") { req in
                try req.content.encode(payload, as: .json)
            }
        } catch {
            app.logger.error("editMessageText failed: \(error.localizedDescription)")
        }
    }

    static func answerCallbackQuery(
        _ app: Application,
        api: String,
        callbackQueryId: String,
        text: String? = nil,
        showAlert: Bool? = nil
    ) async {
        let payload = AnswerCallbackPayload(
            callback_query_id: callbackQueryId,
            text: text,
            show_alert: showAlert
        )
        do {
            _ = try await app.client.post("\(api)/answerCallbackQuery") { req in
                try req.content.encode(payload, as: .json)
            }
        } catch {
            app.logger.error("answerCallbackQuery failed: \(error.localizedDescription)")
        }
    }

    static func editMessageReplyMarkup(
        _ app: Application,
        api: String,
        chatId: Int64,
        messageId: Int,
        inlineMarkup: TgInlineKeyboardMarkup?
    ) async {
        let payload = EditMessageReplyMarkupPayload(
            chat_id: chatId,
            message_id: messageId,
            reply_markup: inlineMarkup
        )
        do {
            _ = try await app.client.post("\(api)/editMessageReplyMarkup") { req in
                try req.content.encode(payload, as: .json)
            }
        } catch {
            app.logger.error("editMessageReplyMarkup failed: \(error.localizedDescription)")
        }
    }

    // MARK: sendDocument (рабочая версия без encodeMultipart)
    public static func sendDocument(
        _ app: Application,
        api: String,
        chatId: Int64,
        filePath: String,
        caption: String? = nil
    ) async throws {
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
