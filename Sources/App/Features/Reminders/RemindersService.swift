//
//  RemindersService.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 18.11.2025.
//

import Vapor

final class RemindersService {

    private(set) var messages: [String] = []

    private let app: Application
    private let client: Client
    private let chatId: String
    private let botToken: String

    init(app: Application) {
        self.app = app
        self.client = app.client
        self.chatId = Environment.get("REMINDER_CHAT_ID") ?? ""
        self.botToken = Environment.get("BOT_TOKEN") ?? ""
        loadMessages(app: app)
        app.logger.info("RemindersService initialized. chatId=\(chatId), tokenEmpty=\(botToken.isEmpty)")
    }

    private func loadMessages(app: Application) {
        let filePath = app.directory.resourcesDirectory + "Reminders/messages.json"

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let decoded = try JSONDecoder().decode([String].self, from: data)
            self.messages = decoded
            app.logger.info("RemindersService: loaded \(messages.count) reminder messages")
        } catch {
            app.logger.error("RemindersService: failed to load messages.json: \(error)")
            self.messages = ["Не забывайте говорить спасибо коллегам 🙂"]
        }
    }

    func sendRandomReminder() {
        guard !chatId.isEmpty else {
            app.logger.warning("REMINDER_CHAT_ID is empty, skip reminder")
            return
        }
        guard !botToken.isEmpty else {
            app.logger.warning("BOT_TOKEN is empty, skip reminder")
            return
        }
        guard let msg = messages.randomElement() else {
            app.logger.warning("No reminder messages loaded, skip reminder")
            return
        }

        struct Payload: Content {
            let chat_id: String
            let text: String
        }

        let uri = URI(string: "https://api.telegram.org/bot\(botToken)/sendMessage")
        let payload = Payload(chat_id: chatId, text: msg)

        Task {
            do {
                _ = try await client.post(uri, content: payload)
                app.logger.info("Reminder sent to chat \(chatId)")
            } catch {
                app.logger.error("Failed to send reminder: \(error)")
            }
        }
    }
}
