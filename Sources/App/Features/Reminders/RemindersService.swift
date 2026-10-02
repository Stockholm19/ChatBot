//
//  RemindersService.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 18.11.2025.
//
//  Личные напоминания: бот пишет каждому участнику в ЛС.
//  Тех, кто сегодня уже сказал спасибо, не беспокоим.
//

import Vapor

struct RemindersService {

    static let namePlaceholder = "{name}"
    static let fallbackMessage = "Есть за что сказать спасибо сегодня? 💌"

    let app: Application
    let api: String
    let messages: [String]

    static func loadMessages(app: Application) -> [String] {
        let filePath = app.directory.resourcesDirectory + "Reminders/messages.json"
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let decoded = try JSONDecoder().decode([String].self, from: data)
            app.logger.info("RemindersService: loaded \(decoded.count) reminder messages")
            return decoded.isEmpty ? [fallbackMessage] : decoded
        } catch {
            app.logger.error("RemindersService: failed to load messages.json: \(error)")
            return [fallbackMessage]
        }
    }

    /// Выбирает текст напоминания. `{name}` подставляется, только если «второй половинке» есть однозначное имя;
    /// иначе используются тексты без плейсхолдера.
    static func composeMessage(from messages: [String], otherName: String?) -> String {
        let candidates: [String]
        if let otherName {
            candidates = messages.map { $0.replacingOccurrences(of: namePlaceholder, with: otherName.htmlEscaped) }
        } else {
            candidates = messages.filter { !$0.contains(namePlaceholder) }
        }
        let text = candidates.randomElement() ?? fallbackMessage
        return text + "\n\nНажми «\(KeyboardBuilder.MainMenuButton.sayThanks)» в меню."
    }

    func sendReminders() async {
        let participants: [Employee]
        do {
            participants = try await FluentEmployeesRepo(db: app.db).activeLinked()
        } catch {
            app.logger.error("RemindersService: failed to load participants: \(error)")
            return
        }

        let kudos = KudosService(db: app.db)
        var sent = 0

        for participant in participants {
            guard let chatId = participant.telegramId, let participantId = participant.id else { continue }

            if (try? await kudos.hasSentToday(employeeId: participantId)) == true {
                continue
            }

            let others = participants.filter { $0.id != participantId }
            let otherName = others.count == 1 ? others.first?.fullName : nil
            let text = Self.composeMessage(from: messages, otherName: otherName)

            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: text)
            sent += 1
        }

        app.logger.info("RemindersService: personal reminders sent=\(sent) participants=\(participants.count)")
    }
}
