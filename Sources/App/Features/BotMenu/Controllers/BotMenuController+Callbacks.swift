//
//  BotMenuController+Callbacks.swift
//  ChatBot
//

import Vapor
import Fluent
import Foundation

extension BotMenuController {

    private enum CallbackAction {
        case page(Int)
        case pick(UUID)
        case back
    }

    private enum CallbackScope: String {
        case emp
        case adminDeactivate = "adm:deact"
        case adminArchive = "adm:arch"
        case adminEditName = "adm:edit"
        case adminBind = "adm:bind"
        case adminChange = "adm:change"
        case adminLink = "adm:link"

        var expectedState: SessionState {
            switch self {
            case .emp: return .choosingEmployee
            case .adminDeactivate: return .adminDeactivateChoose
            case .adminArchive: return .adminArchiveChoose
            case .adminEditName: return .adminEditNameChoose
            case .adminBind: return .adminTelegramBindChoose
            case .adminChange: return .adminTelegramChangeChoose
            case .adminLink: return .adminLinkChoose
            }
        }
    }

    static func handleCallback(
        app: Application,
        api: String,
        query: TgCallbackQuery,
        sessions: SessionStore,
        db: Database
    ) async {
        guard let callbackMessage = query.message else {
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id)
            return
        }

        let chatId = callbackMessage.chat.id
        let session = await sessions.get(chatId) ?? Session(state: .mainMenu)
        let data = (query.data ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard let (scope, action) = parseCallbackData(data) else {
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id)
            return
        }

        guard session.state == scope.expectedState else {
            await TelegramService.answerCallbackQuery(
                app,
                api: api,
                callbackQueryId: query.id,
                text: "Этот список уже неактуален.",
                showAlert: false
            )
            return
        }

        switch scope {
        case .emp:
            await handleEmployeeCallbacks(
                app: app,
                api: api,
                query: query,
                callbackMessage: callbackMessage,
                action: action,
                sessions: sessions,
                db: db
            )
        default:
            await handleAdminCallbacks(
                app: app,
                api: api,
                query: query,
                callbackMessage: callbackMessage,
                scope: scope,
                action: action,
                sessions: sessions,
                db: db
            )
        }
    }

    private static func handleEmployeeCallbacks(
        app: Application,
        api: String,
        query: TgCallbackQuery,
        callbackMessage: TgCallbackMessage,
        action: CallbackAction,
        sessions: SessionStore,
        db: Database
    ) async {
        let chatId = callbackMessage.chat.id

        switch action {
        case .page(let requestedPage):
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id)
            await showEmployeesPage(
                app: app,
                api: api,
                chatId: chatId,
                sessions: sessions,
                db: db,
                page: requestedPage,
                editMessageId: callbackMessage.message_id
            )

        case .back:
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id)
            await TelegramService.editMessageText(
                app,
                api: api,
                chatId: chatId,
                messageId: callbackMessage.message_id,
                text: "Выбор сотрудника закрыт.",
                inlineMarkup: nil
            )
            let isUserAdmin = isAdmin(userId: query.from.id, username: query.from.username)
            await sessions.set(chatId, Session(state: .thanksMenu))
            await TelegramService.sendMessage(
                app,
                api: api,
                chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isUserAdmin)
            )

        case .pick(let employeeId):
            guard let employee = try? await Employee.find(employeeId, on: db),
                  employee.isActive,
                  employee.telegramId != nil else {
                await TelegramService.answerCallbackQuery(
                    app,
                    api: api,
                    callbackQueryId: query.id,
                    text: "Сотрудник недоступен. Обновите список.",
                    showAlert: true
                )
                return
            }

            let senderEmployeeID = try? await Employee.query(on: db)
                .filter(\.$telegramId == query.from.id)
                .first()?
                .requireID()

            if let sid = senderEmployeeID, sid == employeeId {
                await TelegramService.answerCallbackQuery(
                    app,
                    api: api,
                    callbackQueryId: query.id,
                    text: "Нельзя отправить спасибо самому себе 🙂",
                    showAlert: true
                )
                return
            }

            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id)
            await TelegramService.editMessageText(
                app,
                api: api,
                chatId: chatId,
                messageId: callbackMessage.message_id,
                text: "Выбран сотрудник: \(employee.fullName)",
                inlineMarkup: nil
            )

            let currentPage = (await sessions.get(chatId))?.page
            await sessions.set(chatId, Session(state: .awaitingReason, to: nil, page: currentPage, chosenEmployeeId: employeeId))
            await TelegramService.sendMessage(
                app,
                api: api,
                chatId: chatId,
                text: "Напиши короткое сообщение, за что \(employee.fullName) получит благодарность. 🌟 (от \(minReasonLength) символов)",
                replyMarkup: KeyboardBuilder.reasonMenu()
            )
        }
    }

    private static func handleAdminCallbacks(
        app: Application,
        api: String,
        query: TgCallbackQuery,
        callbackMessage: TgCallbackMessage,
        scope: CallbackScope,
        action: CallbackAction,
        sessions: SessionStore,
        db: Database
    ) async {
        let chatId = callbackMessage.chat.id

        switch action {
        case .page(let requestedPage):
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id)
            await showAdminPageForScope(
                app: app,
                api: api,
                chatId: chatId,
                sessions: sessions,
                db: db,
                scope: scope,
                page: requestedPage,
                editMessageId: callbackMessage.message_id
            )

        case .back:
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id)
            await TelegramService.editMessageText(
                app,
                api: api,
                chatId: chatId,
                messageId: callbackMessage.message_id,
                text: "Список закрыт.",
                inlineMarkup: nil
            )
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Админка:", replyMarkup: KeyboardBuilder.adminMenu())

        case .pick(let employeeId):
            await handleAdminPick(
                app: app,
                api: api,
                query: query,
                callbackMessage: callbackMessage,
                scope: scope,
                employeeId: employeeId,
                sessions: sessions,
                db: db
            )
        }
    }

    private static func showAdminPageForScope(
        app: Application,
        api: String,
        chatId: Int64,
        sessions: SessionStore,
        db: Database,
        scope: CallbackScope,
        page: Int,
        editMessageId: Int
    ) async {
        switch scope {
        case .adminDeactivate:
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page, active: true, targetState: .adminDeactivateChoose, editMessageId: editMessageId)
        case .adminArchive:
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page, active: false, targetState: .adminArchiveChoose, editMessageId: editMessageId)
        case .adminEditName:
            await showAdminEditNameEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page, editMessageId: editMessageId)
        case .adminBind:
            await showAdminTelegramBindEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page, editMessageId: editMessageId)
        case .adminChange:
            await showAdminTelegramChangeEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page, editMessageId: editMessageId)
        case .adminLink:
            await showAdminLinkEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page, editMessageId: editMessageId)
        case .emp:
            break
        }
    }

    private static func handleAdminPick(
        app: Application,
        api: String,
        query: TgCallbackQuery,
        callbackMessage: TgCallbackMessage,
        scope: CallbackScope,
        employeeId: UUID,
        sessions: SessionStore,
        db: Database
    ) async {
        let chatId = callbackMessage.chat.id
        guard let emp = try? await Employee.find(employeeId, on: db) else {
            await TelegramService.answerCallbackQuery(
                app,
                api: api,
                callbackQueryId: query.id,
                text: "Сотрудник не найден.",
                showAlert: true
            )
            return
        }

        var session = await sessions.get(chatId) ?? Session()
        session.selectedEmployeeId = employeeId
        await sessions.set(chatId, session)

        await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: query.id)
        await TelegramService.editMessageText(
            app,
            api: api,
            chatId: chatId,
            messageId: callbackMessage.message_id,
            text: "Выбран сотрудник: \(emp.fullName)",
            inlineMarkup: nil
        )

        switch scope {
        case .adminDeactivate:
            session.state = .adminDeactivateConfirm
            await sessions.set(chatId, session)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Деактивировать \(emp.fullName)?", replyMarkup: KeyboardBuilder.yesNo())

        case .adminArchive:
            session.state = .adminArchiveActions
            await sessions.set(chatId, session)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Выбран сотрудник: \(emp.fullName)\nЧто сделать?", replyMarkup: KeyboardBuilder.adminArchiveActionsMenu())

        case .adminEditName:
            session.state = .adminEditNameAsk
            session.draftFullName = nil
            await sessions.set(chatId, session)
            await TelegramService.sendMessage(
                app,
                api: api,
                chatId: chatId,
                text: "Текущее ФИО: \(emp.fullName)\n\nВведи новое ФИО (например: Иванов Иван)",
                replyMarkup: KeyboardBuilder.back()
            )

        case .adminBind:
            session.state = .adminTelegramBindAwaitForward
            await sessions.set(chatId, session)
            await TelegramService.sendMessage(
                app,
                api: api,
                chatId: chatId,
                text: "Выбран сотрудник: \(emp.fullName)\nTelegram не указан. Перешли сообщение от сотрудника.\nЕсли Telegram скрыт в пересылках, нажмите «🔗 Получить код» и отправьте его сотруднику.",
                replyMarkup: KeyboardBuilder.adminTelegramForwardMenuBind()
            )

        case .adminChange:
            session.state = .adminTelegramChangeAwaitForward
            await sessions.set(chatId, session)
            let currentTgText = emp.telegramId.map { "Текущий Telegram ID: <code>\($0)</code>" } ?? "Текущий Telegram ID: <code>не указан</code>"
            await TelegramService.sendMessage(
                app,
                api: api,
                chatId: chatId,
                text: "Выбран сотрудник: \(emp.fullName)\n\(currentTgText)\n\nПерешли сообщение от аккаунта сотрудника.\nЕсли Telegram скрыт, нажмите «🔗 Получить код».",
                replyMarkup: KeyboardBuilder.adminTelegramForwardMenuChange()
            )

        case .adminLink:
            await handleAdminTelegramGenerateCode(app: app, api: api, chatId: chatId, userId: query.from.id, sessions: sessions, db: db)
            await sessions.set(chatId, Session(state: .adminMenu))

        case .emp:
            break
        }
    }

    private static func parseCallbackData(_ data: String) -> (scope: CallbackScope, action: CallbackAction)? {
        if let action = parseAction(data: data, prefix: CallbackScope.emp.rawValue) {
            return (.emp, action)
        }

        let adminScopes: [CallbackScope] = [.adminDeactivate, .adminArchive, .adminEditName, .adminBind, .adminChange, .adminLink]
        for scope in adminScopes {
            if let action = parseAction(data: data, prefix: scope.rawValue) {
                return (scope, action)
            }
        }

        return nil
    }

    private static func parseAction(data: String, prefix: String) -> CallbackAction? {
        if data == "\(prefix):back" {
            return .back
        }

        if data.hasPrefix("\(prefix):page:"), let page = Int(data.replacingOccurrences(of: "\(prefix):page:", with: "")) {
            return .page(page)
        }

        if data.hasPrefix("\(prefix):pick:") {
            let value = data.replacingOccurrences(of: "\(prefix):pick:", with: "")
            if let id = UUID(uuidString: value) {
                return .pick(id)
            }
        }

        return nil
    }
}
