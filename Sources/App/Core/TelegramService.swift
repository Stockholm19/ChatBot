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

public enum TelegramService {

    // MARK: Polling getUpdates
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
                app.logger.warning("poll error: \(error.localizedDescription)")
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
