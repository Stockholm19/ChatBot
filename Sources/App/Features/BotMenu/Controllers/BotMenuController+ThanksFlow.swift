//
//  BotMenuController+ThanksFlow.swift
//  ChatBot
//

import Vapor
import Fluent

extension BotMenuController {

    /// Точка входа в сценарий «Сказать спасибо».
    /// Если получатель может быть только один — пропускаем выбор и сразу просим текст.
    static func startThanksFlow(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        sessions: SessionStore,
        db: Database,
        isUserAdmin: Bool
    ) async {
        let participants = (try? await FluentEmployeesRepo(db: db).activeLinked()) ?? []
        let recipients = participants.filter { $0.telegramId != userId }

        if recipients.isEmpty {
            let hint = isUserAdmin ? "\nДобавить участника можно в ⚙️ Настройках." : ""
            await showMainMenu(
                app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin,
                text: "Пока некому сказать спасибо — других участников ещё нет.\(hint)"
            )
            return
        }

        if recipients.count == 1, let recipient = recipients.first, let recipientId = recipient.id {
            await sessions.set(chatId, Session(state: .awaitingReason, page: nil, chosenEmployeeId: recipientId))
            await askForReason(app: app, api: api, chatId: chatId, recipientName: recipient.fullName, canGoBack: false)
            return
        }

        await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0)
    }

    static func askForReason(app: Application, api: String, chatId: Int64, recipientName: String, canGoBack: Bool) async {
        await TelegramService.sendMessage(
            app, api: api, chatId: chatId,
            text: "Напиши, за что спасибо — <b>\(recipientName.htmlEscaped)</b> получит это сообщение 💌",
            replyMarkup: KeyboardBuilder.reasonMenu(showBack: canGoBack)
        )
    }

    static func handleThanksFlow(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        username: String?,
        message: TgMessage,
        sessions: SessionStore,
        db: Database,
        state: SessionState,
        text: String,
        isUserAdmin: Bool
    ) async {
        let trimmed = message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let session = await sessions.get(chatId) ?? Session()

        switch (state, text) {
        case (.choosingEmployee, "<"), (.choosingEmployee, "⬅"), (.choosingEmployee, "←"), (.choosingEmployee, "⭠"):
            let page = session.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))

        case (.choosingEmployee, ">"), (.choosingEmployee, "➡"), (.choosingEmployee, "→"), (.choosingEmployee, "⭢"):
            let page = session.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1)

        case (.choosingEmployee, "← Назад"):
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showMainMenu(app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin)

        case (.choosingEmployee, _):
            await selectRecipientByText(app: app, api: api, chatId: chatId, userId: userId, input: trimmed, sessions: sessions, db: db)

        case (.awaitingRecipient, _):
            // Устаревший сценарий ввода @username — возвращаем в главное меню
            await showMainMenu(app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin)

        case (.awaitingReason, "← Назад"):
            // page == nil — получатель был выбран автоматически, списка не было
            guard let page = session.page else {
                await showMainMenu(app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin)
                return
            }
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page)

        case (.awaitingReason, "Отмена"):
            await showMainMenu(
                app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin,
                text: "Хорошо, отменили."
            )

        case (.awaitingReason, _) where trimmed.count < minReasonLength:
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Напиши хотя бы пару слов 🙂",
                replyMarkup: KeyboardBuilder.reasonMenu(showBack: session.page != nil)
            )

        case (.awaitingReason, _):
            await saveThanks(
                app: app, api: api, chatId: chatId, userId: userId, username: username,
                reason: trimmed, recipientId: session.chosenEmployeeId,
                sessions: sessions, db: db, isUserAdmin: isUserAdmin
            )

        default:
            break
        }
    }

    // MARK: - Private

    /// Выбор получателя текстом (кнопки старой reply-клавиатуры, формат «Имя» или «Имя (N)»)
    private static func selectRecipientByText(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        input: String,
        sessions: SessionStore,
        db: Database
    ) async {
        let sel = parseEmployeeSelection(input)
        let candidates = ((try? await Employee.query(on: db)
            .filter(\.$isActive == true)
            .filter(\.$telegramId != nil)
            .filter(\.$fullName == sel.name)
            .all()) ?? [])
            .sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }

        let chosen: Employee?
        if let idx = sel.index, idx >= 1, idx <= candidates.count {
            chosen = candidates[idx - 1]
        } else {
            chosen = candidates.first
        }

        guard let recipient = chosen, let recipientId = recipient.id else {
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Не нашёл такого участника. Листай </> или выбери из списка."
            )
            return
        }

        if recipient.telegramId == userId {
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Себе спасибо тоже важно говорить, но здесь — только другим 🙂",
                replyMarkup: KeyboardBuilder.backToEmployeesList()
            )
            let page = (await sessions.get(chatId))?.page
            await sessions.set(chatId, Session(state: .choosingEmployee, page: page))
            return
        }

        let currentPage = (await sessions.get(chatId))?.page
        await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
        await sessions.set(chatId, Session(state: .awaitingReason, page: currentPage ?? 0, chosenEmployeeId: recipientId))
        await askForReason(app: app, api: api, chatId: chatId, recipientName: recipient.fullName, canGoBack: true)
    }

    private static func saveThanks(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        username: String?,
        reason: String,
        recipientId: UUID?,
        sessions: SessionStore,
        db: Database,
        isUserAdmin: Bool
    ) async {
        guard let recipientId, let recipient = try? await Employee.find(recipientId, on: db) else {
            await showMainMenu(
                app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin,
                text: "Не получилось найти получателя. Попробуй ещё раз."
            )
            return
        }

        let sender = await currentParticipant(userId: userId, db: db)
        if let sender, sender.id == recipientId {
            await showMainMenu(
                app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin,
                text: "Себе спасибо тоже важно говорить, но здесь — только другим 🙂"
            )
            return
        }

        let fromUN = normalizeUsername(username ?? "unknown")
        let kudos = Kudos(
            ts: Date(),
            fromUserId: userId ?? 0,
            fromUsername: fromUN,
            fromName: username ?? fromUN,
            toUsername: "@unknown",
            reason: reason,
            employeeId: recipientId,
            fromEmployeeId: sender?.id
        )

        do {
            try await kudos.save(on: db)
        } catch {
            app.logger.error("thanks_save_failed: \(error)")
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Не получилось сохранить спасибо 😔 Попробуй ещё раз чуть позже.",
                replyMarkup: KeyboardBuilder.reasonMenu(showBack: (await sessions.get(chatId))?.page != nil)
            )
            return
        }

        if let recipientTgId = recipient.telegramId, let kudosId = kudos.id {
            let senderName = sender?.fullName ?? username ?? fromUN
            let notifyText = """
            💌 <b>Тебе спасибо!</b>

            От: \(senderName.htmlEscaped)
            «\(reason.htmlEscaped)»
            """
            await TelegramService.sendMessage(
                app, api: api, chatId: recipientTgId,
                text: notifyText,
                inlineMarkup: KeyboardBuilder.reactionsInline(kudosId: kudosId)
            )
        }

        await showMainMenu(
            app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin,
            text: "Отправлено! <b>\(recipient.fullName.htmlEscaped)</b> получит твоё спасибо 💛"
        )
    }
}
