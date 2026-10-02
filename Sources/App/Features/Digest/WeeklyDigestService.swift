//
//  WeeklyDigestService.swift
//  ChatBot
//
//  Рассылает каждому участнику личные итоги последних 7 дней.
//

import Vapor

struct WeeklyDigestService {
    let app: Application
    let api: String

    func sendDigests() async {
        let participants: [Employee]
        do {
            participants = try await FluentEmployeesRepo(db: app.db).activeLinked()
        } catch {
            app.logger.error("WeeklyDigestService: failed to load participants: \(error)")
            return
        }

        let kudos = KudosService(db: app.db)
        for participant in participants {
            guard let chatId = participant.telegramId, let participantId = participant.id else { continue }
            do {
                let summary = try await kudos.weeklySummary(for: participantId)
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: Self.format(summary))
            } catch {
                app.logger.error("WeeklyDigestService: failed for participant \(participantId): \(error)")
            }
        }
        app.logger.info("WeeklyDigestService: digest sent to \(participants.count) participants")
    }

    static func format(_ summary: KudosService.WeeklySummary) -> String {
        guard summary.sent + summary.received > 0 else {
            return """
            🗓 <b>Итоги недели</b>

            На этой неделе спасибо не звучали. Может, самое время? 💌
            """
        }

        var text = """
        🗓 <b>Итоги недели</b>

        💌 Ты сказал(а) спасибо: \(summary.sent)
        💛 Тебе сказали спасибо: \(summary.received)
        """

        if let highlight = summary.highlight {
            text += """


            ✨ Одно из спасибо этой недели — от \(highlight.senderDisplayName.htmlEscaped):
            «\(highlight.reason.truncated(to: 300).htmlEscaped)»
            """
        }
        return text
    }
}
