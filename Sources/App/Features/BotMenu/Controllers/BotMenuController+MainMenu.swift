//
//  BotMenuController+MainMenu.swift
//  ChatBot
//

import Vapor
import Fluent

extension BotMenuController {

    /// Показывает главное меню и сбрасывает сессию
    static func showMainMenu(
        app: Application,
        api: String,
        chatId: Int64,
        sessions: SessionStore,
        isUserAdmin: Bool,
        text: String = "Главное меню:"
    ) async {
        await sessions.set(chatId, Session(state: .mainMenu))
        await TelegramService.sendMessage(
            app, api: api, chatId: chatId,
            text: text,
            replyMarkup: KeyboardBuilder.mainMenu(isAdmin: isUserAdmin)
        )
    }

    static func handleMainMenu(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        text: String,
        sessions: SessionStore,
        db: Database,
        isUserAdmin: Bool
    ) async {
        switch KeyboardBuilder.MainMenuAction(text: text) {
        case .sayThanks:
            await startThanksFlow(app: app, api: api, chatId: chatId, userId: userId, sessions: sessions, db: db, isUserAdmin: isUserAdmin)

        case .feed:
            await showFeed(app: app, api: api, chatId: chatId, userId: userId, db: db, isUserAdmin: isUserAdmin)

        case .jar:
            await showRandomFromJar(app: app, api: api, chatId: chatId, userId: userId, db: db, isUserAdmin: isUserAdmin)

        case .stats:
            await showPersonalStats(app: app, api: api, chatId: chatId, userId: userId, sessions: sessions, db: db)

        case .settings where isUserAdmin:
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Настройки:",
                replyMarkup: KeyboardBuilder.adminMenu()
            )

        default:
            await showMainMenu(
                app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin,
                text: "Не понимаю эту команду 🙂 Выбери действие в меню ниже."
            )
        }
    }

    // MARK: - Participant lookup

    /// Участник, связанный с текущим Telegram-аккаунтом
    static func currentParticipant(userId: Int64?, db: Database) async -> Employee? {
        guard let userId else { return nil }
        return try? await FluentEmployeesRepo(db: db).findByTelegramId(userId)
    }

    private static func sendNotLinkedHint(app: Application, api: String, chatId: Int64, isUserAdmin: Bool) async {
        await TelegramService.sendMessage(
            app, api: api, chatId: chatId,
            text: "Твой Telegram пока не привязан к участнику. Добавь себя в ⚙️ Настройках или попроси код привязки.",
            replyMarkup: KeyboardBuilder.mainMenu(isAdmin: isUserAdmin)
        )
    }

    // MARK: - Feed

    static let feedLimit = 10

    static func showFeed(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        db: Database,
        isUserAdmin: Bool
    ) async {
        guard let me = await currentParticipant(userId: userId, db: db), let meID = me.id else {
            await sendNotLinkedHint(app: app, api: api, chatId: chatId, isUserAdmin: isUserAdmin)
            return
        }

        let items = (try? await KudosService(db: db).recent(involving: meID, limit: feedLimit)) ?? []
        let text: String
        if items.isEmpty {
            text = "Здесь пока пусто. Самое время сказать первое спасибо 💌"
        } else {
            let lines = items.map { formatFeedItem($0, viewerId: meID) }
            text = "📜 <b>Последние спасибо</b>\n\n" + lines.joined(separator: "\n\n")
        }

        await TelegramService.sendMessage(
            app, api: api, chatId: chatId,
            text: text,
            replyMarkup: KeyboardBuilder.mainMenu(isAdmin: isUserAdmin)
        )
    }

    /// Одна запись ленты: дата, направление, реакция и текст
    static func formatFeedItem(_ kudos: Kudos, viewerId: UUID) -> String {
        let direction: String
        if kudos.$fromEmployee.id == viewerId {
            direction = "Ты → \(kudos.recipientDisplayName.htmlEscaped)"
        } else {
            direction = "\(kudos.senderDisplayName.htmlEscaped) → тебе"
        }
        let reaction = kudos.reaction.map { " \($0)" } ?? ""
        let reason = kudos.reason.truncated(to: 300).htmlEscaped
        return "<i>\(shortDate(kudos.ts))</i> · \(direction)\(reaction)\n«\(reason)»"
    }

    static func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMMM yyyy"
        return df.string(from: date)
    }

    // MARK: - Jar

    static func showRandomFromJar(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        db: Database,
        isUserAdmin: Bool
    ) async {
        guard let me = await currentParticipant(userId: userId, db: db), let meID = me.id else {
            await sendNotLinkedHint(app: app, api: api, chatId: chatId, isUserAdmin: isUserAdmin)
            return
        }

        let text: String
        if let kudos = try? await KudosService(db: db).randomReceived(by: meID) {
            text = """
            🫙 <b>Из банки спасибо</b>

            От: \(kudos.senderDisplayName.htmlEscaped) · <i>\(shortDate(kudos.ts))</i>
            «\(kudos.reason.htmlEscaped)»
            """
        } else {
            text = "Банка пока пустая — как только тебе скажут спасибо, оно появится здесь 🫙"
        }

        await TelegramService.sendMessage(
            app, api: api, chatId: chatId,
            text: text,
            replyMarkup: KeyboardBuilder.mainMenu(isAdmin: isUserAdmin)
        )
    }
}
