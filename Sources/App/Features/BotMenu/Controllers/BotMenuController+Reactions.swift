//
//  BotMenuController+Reactions.swift
//  ChatBot
//
//  Реакция получателя на спасибо: кнопки ❤️ 🤗 🥹 под уведомлением.
//  Отправитель получает ответ, а реакция сохраняется и видна в ленте.
//

import Vapor
import Fluent

extension BotMenuController {

    /// Разбирает callback_data вида `react:<index>:<kudosId>`
    static func parseReactionCallback(_ data: String) -> (emoji: String, kudosId: UUID)? {
        let parts = data.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "react",
              let index = Int(parts[1]),
              KeyboardBuilder.reactions.indices.contains(index),
              let kudosId = UUID(uuidString: String(parts[2])) else {
            return nil
        }
        return (KeyboardBuilder.reactions[index], kudosId)
    }

    static func handleReactionCallback(
        app: Application,
        api: String,
        query: TgCallbackQuery,
        callbackMessage: TgCallbackMessage,
        kudosId: UUID,
        emoji: String,
        db: Database
    ) async {
        let outcome: KudosService.ReactionOutcome
        do {
            outcome = try await KudosService(db: db).react(kudosId: kudosId, byTelegramId: query.from.id, reaction: emoji)
        } catch {
            app.logger.error("reaction_save_failed: \(error)")
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id, text: "Не получилось, попробуй ещё раз", showAlert: false)
            return
        }

        switch outcome {
        case .notFound:
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id, text: "Это спасибо больше не найдено", showAlert: false)

        case .notRecipient:
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id, text: "Отреагировать может только получатель", showAlert: false)

        case .alreadyReacted(let existing):
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id, text: "Ты уже ответил(а) \(existing)", showAlert: false)
            await removeReactionButtons(app: app, api: api, callbackMessage: callbackMessage)

        case .reacted(let kudos):
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id, text: "Отправлено \(emoji)", showAlert: false)
            await removeReactionButtons(app: app, api: api, callbackMessage: callbackMessage)

            let senderTgId = kudos.fromEmployee?.telegramId ?? kudos.fromUserId
            guard senderTgId != 0 else { return }
            await TelegramService.sendMessage(
                app, api: api, chatId: senderTgId,
                text: """
                \(emoji) <b>\(kudos.recipientDisplayName.htmlEscaped)</b> ответил(а) на твоё спасибо:
                «\(kudos.reason.truncated(to: 300).htmlEscaped)»
                """
            )
        }
    }

    private static func removeReactionButtons(app: Application, api: String, callbackMessage: TgCallbackMessage) async {
        await TelegramService.editMessageReplyMarkup(
            app,
            api: api,
            chatId: callbackMessage.chat.id,
            messageId: callbackMessage.message_id,
            inlineMarkup: nil
        )
    }
}
