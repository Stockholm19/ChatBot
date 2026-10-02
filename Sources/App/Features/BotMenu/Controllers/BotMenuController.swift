//
//  BotMenuController.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 25.09.2025.
//

import Vapor
import Fluent

enum BotMenuController {

    // Минимальная длина текста благодарности: короткое «спасибо за ужин» — тоже спасибо
    static let minReasonLength = 3

    // MARK: - Roles

    /// Проверка прав администратора: поддерживает и ADMIN_IDS (числовые Telegram ID),
    /// и ADMIN_USERNAMES (ники без @). Достаточно совпадения по одному из списков.
    static func isAdmin(userId: Int64?, username: String?) -> Bool {
        var ok = false
        if let id = userId {
            let rawIDs = (Environment.get("ADMIN_IDS") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ids = Set(rawIDs.split(separator: ",").compactMap {
                Int64($0.trimmingCharacters(in: .whitespacesAndNewlines))
            })
            ok = ok || ids.contains(id)
        }
        if let u = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            let rawUN = (Environment.get("ADMIN_USERNAMES") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let uns = Set(rawUN.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            })
            ok = ok || uns.contains(u)
        }
        return ok
    }

    // MARK: - Entry points

    static func handleStart(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        username: String?,
        sessions: SessionStore
    ) async {
        // Игнорируем группы и каналы: бот показывает меню только в личных чатах
        if chatId <= 0 {
            return
        }

        await showMainMenu(
            app: app, api: api, chatId: chatId, sessions: sessions,
            isUserAdmin: isAdmin(userId: userId, username: username),
            text: """
            Привет! 👋

            Это наш маленький бот для «спасибо». Говори спасибо за ужин, за поддержку, за то, что рядом, — а я передам и бережно всё сохраню.

            💌 <b>Сказать спасибо</b> — написать благодарность
            📜 <b>Наши спасибо</b> — последние тёплые слова
            🫙 <b>Вспомнить</b> — достать случайное спасибо из банки
            📊 <b>Статистика</b> — сколько спасибо уже накопилось
            """
        )
    }

    static func handleMessage(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        username: String?,
        message: TgMessage,
        sessions: SessionStore,
        db: Database
    ) async {
        let text = (message.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Игнорируем все сообщения из групп и каналов — бот отвечает только в личке
        if chatId <= 0 {
            return
        }
        
        let session = await sessions.get(chatId) ?? Session(state: .mainMenu)
        let state = session.state
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = trimmed.normalizedNav
        
        let isUserAdmin = isAdmin(userId: userId, username: username)
        app.logger.info("BotMenu: state=\(state), text=\(t), isAdmin=\(isUserAdmin)")

        // Debug: /whoami — показывает распознанный userId/username и env (только для админов)
        if trimmed == "/whoami" {
            guard isUserAdmin else {
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Команда недоступна.")
                return
            }
            let msg = """
            userId: \(userId.map(String.init) ?? "nil")
            username: \(username ?? "nil")
            ADMIN_IDS: \(Environment.get("ADMIN_IDS") ?? "(nil)")
            ADMIN_USERNAMES: \(Environment.get("ADMIN_USERNAMES") ?? "(nil)")
            isAdmin: \(isAdmin(userId: userId, username: username) ? "true" : "false")
            """
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg)
            return
        }
            
        // Глобальная обработка возврата к списку участников
        if t == "← Назад к списку" {
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            let page = session.page ?? 0
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page)
            return
        }
        
        // Защита: если пользователь не админ, но оказался в админских состояниях, возвращаем в главное меню
        if !isUserAdmin {
            switch state {
            case .adminMenu,
                  .adminTelegramMenu, .adminTelegramBindChoose, .adminTelegramBindAwaitForward,
                  .adminTelegramChangeChoose, .adminTelegramChangeAwaitForward,
                  .adminLinkChoose,
                  .adminAddAskName, .adminAddConfirmName, .adminAddAskForward, .adminAddConfirmAccount,
                  .adminDeactivateChoose, .adminDeactivateConfirm,
                  .adminEditNameChoose, .adminEditNameAsk, .adminEditNameConfirm,
                  .adminArchiveChoose, .adminArchiveActions, .adminArchiveConfirm, .adminArchiveDeleteConfirm:
                await showMainMenu(
                    app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: false,
                    text: "Настройки доступны только администратору."
                )
                return
            default:
                break
            }
        }

        switch state {
        case .mainMenu:
            await handleMainMenu(app: app, api: api, chatId: chatId, userId: userId, text: t, sessions: sessions, db: db, isUserAdmin: isUserAdmin)
            
        case .choosingEmployee, .awaitingRecipient, .awaitingReason:
            await handleThanksFlow(app: app, api: api, chatId: chatId, userId: userId, username: username, message: message, sessions: sessions, db: db, state: state, text: t, isUserAdmin: isUserAdmin)
            
        case .statisticsMenu:
            await handleStatsState(app: app, api: api, chatId: chatId, userId: userId, username: username, sessions: sessions, db: db, text: t, isUserAdmin: isUserAdmin)
            
        case .adminMenu:
            await handleAdminMenuState(app: app, api: api, chatId: chatId, text: t, sessions: sessions, db: db, isUserAdmin: isUserAdmin)
            
        case .adminTelegramMenu, .adminTelegramBindChoose, .adminTelegramBindAwaitForward, .adminTelegramChangeChoose, .adminTelegramChangeAwaitForward, .adminLinkChoose:
            await handleAdminTelegramBindState(app: app, api: api, chatId: chatId, userId: userId, message: message, sessions: sessions, db: db, state: state, text: t, trimmed: trimmed)
            
        case .adminAddAskName, .adminAddConfirmName, .adminAddAskForward, .adminAddConfirmAccount, .adminDeactivateChoose, .adminDeactivateConfirm, .adminArchiveChoose, .adminArchiveActions, .adminArchiveConfirm, .adminArchiveDeleteConfirm:
            let fwd = message.forward_from
            await handleAdminEmployeesState(
                app: app,
                api: api,
                chatId: chatId,
                userId: userId,
                username: username,
                sessions: sessions,
                db: db,
                state: state,
                text: t,
                trimmed: trimmed,
                forwardedFromId: fwd?.id,
                forwardedFromUsername: fwd?.username,
                forwardedFromFirstName: fwd?.first_name,
                forwardedFromLastName: fwd?.last_name
            )

        case .adminEditNameChoose, .adminEditNameAsk, .adminEditNameConfirm:
            await handleAdminEmployeesState(
                app: app,
                api: api,
                chatId: chatId,
                userId: userId,
                username: username,
                sessions: sessions,
                db: db,
                state: state,
                text: t,
                trimmed: trimmed
            )
        }
    }
}


extension String {
    /// Убираем вариационные селекторы (FE0E/FE0F) и пробелы по краям.
    var normalizedNav: String {
        let disallowed: [UnicodeScalar] = [UnicodeScalar(0xFE0E)!, UnicodeScalar(0xFE0F)!]
        let filtered = self.unicodeScalars.filter { !disallowed.contains($0) }
        return String(String.UnicodeScalarView(filtered)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
