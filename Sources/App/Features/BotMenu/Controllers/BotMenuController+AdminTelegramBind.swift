//
//  BotMenuController+AdminTelegramBind.swift
//  ChatBot
//

import Vapor
import Fluent

extension BotMenuController {
    
    static func handleAdminTelegramBindState(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        message: TgMessage,
        sessions: SessionStore,
        db: Database,
        state: SessionState,
        text: String,
        trimmed: String
    ) async {
        switch state {
        case .adminTelegramMenu:
            await handleAdminTelegramMenu(app: app, api: api, chatId: chatId, sessions: sessions, db: db, text: text)

        case .adminTelegramBindChoose:
            await handleAdminTelegramBindChoose(app: app, api: api, chatId: chatId, sessions: sessions, db: db, text: text, trimmed: trimmed)

        case .adminTelegramBindAwaitForward:
            await handleAdminTelegramBindAwaitForward(app: app, api: api, chatId: chatId, userId: userId, message: message, sessions: sessions, db: db, text: text)

        case .adminTelegramChangeChoose:
            await handleAdminTelegramChangeChoose(app: app, api: api, chatId: chatId, sessions: sessions, db: db, text: text, trimmed: trimmed)

        case .adminTelegramChangeAwaitForward:
            await handleAdminTelegramChangeAwaitForward(app: app, api: api, chatId: chatId, userId: userId, message: message, sessions: sessions, db: db, text: text)

        case .adminLinkChoose:
             await handleAdminLinkChoose(app: app, api: api, chatId: chatId, userId: userId, sessions: sessions, db: db, text: text, trimmed: trimmed)

        default:
            break
        }
    }
    
    // Internal helpers
    
    private static func handleAdminTelegramMenu(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String) async {
        if text == "➕ Привязать Telegram" {
            await showAdminTelegramBindEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0)
        } else if text == "🔄 Изменить Telegram" {
            await showAdminTelegramChangeEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0)
        } else if text == "← Назад" {
            var session = await sessions.get(chatId) ?? Session()
            session.state = .adminMenu
            await sessions.set(chatId, session)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Раздел администратора:", replyMarkup: KeyboardBuilder.adminMenu())
        }
    }

    private static func handleAdminTelegramBindChoose(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String, trimmed: String) async {
        if ["<", "⬅", "←", "⭠"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminTelegramBindEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))
        } else if [">", "➡", "→", "⭢"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminTelegramBindEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1)
        } else if text == "← Назад" {
            var session = await sessions.get(chatId) ?? Session()
            session.state = .adminTelegramMenu
            await sessions.set(chatId, session)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Выберите действие:", replyMarkup: KeyboardBuilder.adminTelegramMenu())
        } else {
            let sel = parseEmployeeSelection(trimmed)

            let candidates = (try? await Employee.query(on: db)
                .filter(\.$telegramId == nil)
                .filter(\.$fullName == sel.name)
                .all()) ?? []

            let sorted = candidates.sorted { a, b in
                let aId = (try? a.requireID())?.uuidString ?? ""
                let bId = (try? b.requireID())?.uuidString ?? ""
                return aId < bId
            }

            let chosen: Employee?
            if let idx = sel.index, idx > 0, idx <= sorted.count {
                chosen = sorted[idx - 1]
            } else {
                chosen = sorted.first
            }

            if let emp = chosen,
               let empId = try? emp.requireID() {
                var session = await sessions.get(chatId) ?? Session()
                session.selectedEmployeeId = empId
                session.state = .adminTelegramBindAwaitForward
                await sessions.set(chatId, session)
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Выбран сотрудник: \(emp.fullName)\nTelegram не указан. Перешли сообщение от сотрудника.\nЕсли Telegram скрыт в пересылках, нажмите «🔗 Получить код» и отправьте его сотруднику.",
                    replyMarkup: KeyboardBuilder.adminTelegramForwardMenuBind()
                )
            }
        }
    }

    private static func handleAdminTelegramBindAwaitForward(app: Application, api: String, chatId: Int64, userId: Int64?, message: TgMessage, sessions: SessionStore, db: Database, text: String) async {
        if text == "Отмена" {
            await handleAdminTelegramBindCancel(app: app, api: api, chatId: chatId, sessions: sessions, db: db)
        } else if text == "← Назад" {
            var session = await sessions.get(chatId) ?? Session()
            session.state = .adminTelegramBindChoose
            await sessions.set(chatId, session)
            await showAdminTelegramBindEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: session.page ?? 0)
        } else if text == "🔗 Получить код" {
            await handleAdminTelegramGenerateCode(app: app, api: api, chatId: chatId, userId: userId, sessions: sessions, db: db)
        } else if let fwd = message.forward_from {
            await handleAdminTelegramBindForward(app: app, api: api, chatId: chatId, fwdId: fwd.id, sessions: sessions, db: db)
        }
        else {
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Не понял команду. Нажми кнопку ниже.",
                replyMarkup: KeyboardBuilder.adminTelegramForwardMenuBind()
            )
        }
    }

    private static func handleAdminTelegramChangeChoose(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String, trimmed: String) async {
        if ["<", "⬅", "←", "⭠"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminTelegramChangeEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))
        } else if [">", "➡", "→", "⭢"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminTelegramChangeEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1)
        } else if text == "← Назад" {
            var session = await sessions.get(chatId) ?? Session()
            session.state = .adminTelegramMenu
            await sessions.set(chatId, session)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Выберите действие:", replyMarkup: KeyboardBuilder.adminTelegramMenu())
        } else {
            let sel = parseEmployeeSelection(trimmed)

            let candidates = (try? await Employee.query(on: db)
                .filter(\.$isActive == true)
                .filter(\.$telegramId != nil)
                .filter(\.$fullName == sel.name)
                .all()) ?? []

            let sorted = candidates.sorted { a, b in
                let aId = (try? a.requireID())?.uuidString ?? ""
                let bId = (try? b.requireID())?.uuidString ?? ""
                return aId < bId
            }

            let chosen: Employee?
            if let idx = sel.index, idx > 0, idx <= sorted.count {
                chosen = sorted[idx - 1]
            } else {
                chosen = sorted.first
            }

            if let emp = chosen,
               let empId = try? emp.requireID() {
                var session = await sessions.get(chatId) ?? Session()
                session.selectedEmployeeId = empId
                session.state = .adminTelegramChangeAwaitForward
                await sessions.set(chatId, session)

                let currentTgText: String
                if let current = emp.telegramId {
                    currentTgText = "Текущий Telegram ID: <code>\(current)</code>"
                } else {
                    currentTgText = "Текущий Telegram ID: <code>не указан</code>"
                }

                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Выбран сотрудник: \(emp.fullName)\n\(currentTgText)\n\nПерешли сообщение от аккаунта сотрудника.\nЕсли Telegram скрыт, нажмите «🔗 Получить код».",
                    replyMarkup: KeyboardBuilder.adminTelegramForwardMenuChange()
                )
            }
        }
    }

    private static func handleAdminTelegramChangeAwaitForward(app: Application, api: String, chatId: Int64, userId: Int64?, message: TgMessage, sessions: SessionStore, db: Database, text: String) async {
        if text == "Отмена" {
            var s = await sessions.get(chatId) ?? Session()
            s.state = .adminTelegramMenu
            await sessions.set(chatId, s)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отменено.", replyMarkup: KeyboardBuilder.adminTelegramMenu())
        } else if text == "← Назад" {
            var session = await sessions.get(chatId) ?? Session()
            session.state = .adminTelegramChangeChoose
            await sessions.set(chatId, session)
            await showAdminTelegramChangeEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: session.page ?? 0)
        } else if text == "🔗 Получить код" {
            await handleAdminTelegramGenerateCode(app: app, api: api, chatId: chatId, userId: userId, sessions: sessions, db: db)
        } else if let fwd = message.forward_from {
            await handleAdminTelegramChangeForward(app: app, api: api, chatId: chatId, fwdId: fwd.id, sessions: sessions, db: db)
        }
        else {
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Не понял команду. Нажми кнопку ниже.",
                replyMarkup: KeyboardBuilder.adminTelegramForwardMenuChange()
            )
        }
    }
    
    private static func handleAdminLinkChoose(app: Application, api: String, chatId: Int64, userId: Int64?, sessions: SessionStore, db: Database, text: String, trimmed: String) async {
        if ["<", "⬅", "←", "⭠"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminLinkEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))
        } else if [">", "➡", "→", "⭢"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminLinkEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1)
        } else if text == "← Назад" {
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Админка:", replyMarkup: KeyboardBuilder.adminMenu())
        } else {
            let sel = parseEmployeeSelection(trimmed)
            if let emp = try? await Employee.query(on: db).filter(\.$telegramId == nil).filter(\.$fullName == sel.name).first(),
               let empId = try? emp.requireID() {
                var s = await sessions.get(chatId) ?? Session()
                s.selectedEmployeeId = empId
                await sessions.set(chatId, s)
                await handleAdminTelegramGenerateCode(app: app, api: api, chatId: chatId, userId: userId, sessions: sessions, db: db)
                await sessions.set(chatId, Session(state: .adminMenu))
            }
        }
    }

    // Shared helpers
    
    private static func handleAdminTelegramBindCancel(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database) async {
        let empId = (await sessions.get(chatId))?.selectedEmployeeId
        if let empId {
            try? await PendingLink.query(on: db).filter(\.$employee.$id == empId).filter(\.$isUsed == false).delete()
            if let emp = try? await Employee.find(empId, on: db), emp.telegramId == nil && emp.isActive == false {
                try? await emp.delete(on: db)
            }
        }
        await sessions.set(chatId, Session(state: .adminTelegramMenu))
        await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отменено.", replyMarkup: KeyboardBuilder.adminTelegramMenu())
    }

    private static func handleAdminTelegramGenerateCode(app: Application, api: String, chatId: Int64, userId: Int64?, sessions: SessionStore, db: Database) async {
        guard let empId = (await sessions.get(chatId))?.selectedEmployeeId, let emp = try? await Employee.find(empId, on: db) else { return }
        try? await PendingLink.query(on: db).filter(\.$employee.$id == empId).filter(\.$isUsed == false).delete()
        var code = ""
        for _ in 1...5 {
            let c = String(Int.random(in: 100000...999999))
            let existing = try? await PendingLink.query(on: db).filter(\.$code == c).first()
            if existing == nil { code = c; break }
        }
        guard !code.isEmpty else { return }
        try? await PendingLink(code: code, employeeId: empId, createdByAdminTgId: userId, expiresAt: Date().addingTimeInterval(15*60)).save(on: db)
        let msg = """
        Код для <b>\(emp.fullName)</b>:
        <code>/link \(code)</code>

        Отправь эту команду сотруднику. Он должен:
        1) Открыть чат с ботом
        2) Нажать на команду выше (или скопировать) и отправить

        Код действует 15 минут.
        """
        let currentState = (await sessions.get(chatId))?.state
        let kb: TgReplyKeyboard = (currentState == .adminTelegramChangeAwaitForward)
            ? KeyboardBuilder.adminTelegramForwardMenuChange()
            : KeyboardBuilder.adminTelegramForwardMenuBind()
        await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg, replyMarkup: kb)
    }

    private static func handleAdminTelegramBindForward(app: Application, api: String, chatId: Int64, fwdId: Int64, sessions: SessionStore, db: Database) async {
        guard let empId = (await sessions.get(chatId))?.selectedEmployeeId, let emp = try? await Employee.find(empId, on: db) else { return }
        if let conflictingEmp = await checkTelegramIdConflict(db: db, newTelegramId: fwdId, currentEmployeeId: empId) {
            let conflictingName = conflictingEmp.fullName
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Этот Telegram уже привязан к сотруднику \(conflictingName).\nВыберите другой аккаунт или сначала измените привязку у другого сотрудника.",
                replyMarkup: KeyboardBuilder.adminTelegramForwardMenuBind()
            )
            return
        }
        emp.telegramId = fwdId
        emp.isActive = true
        try? await emp.save(on: db)
        try? await PendingLink.query(on: db).filter(\.$employee.$id == empId).delete()
        await TelegramService.sendMessage(
            app, api: api, chatId: chatId,
            text: "✅ Telegram успешно привязан для \(emp.fullName)",
            replyMarkup: KeyboardBuilder.adminTelegramMenu()
        )
        await sessions.set(chatId, Session(state: .adminTelegramMenu))
    }

    private static func handleAdminTelegramChangeForward(app: Application, api: String, chatId: Int64, fwdId: Int64, sessions: SessionStore, db: Database) async {
        guard let empId = (await sessions.get(chatId))?.selectedEmployeeId,
              let emp = try? await Employee.find(empId, on: db) else { return }

        if let conflictingEmp = await checkTelegramIdConflict(db: db, newTelegramId: fwdId, currentEmployeeId: empId) {
            let conflictingName = conflictingEmp.fullName
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Этот Telegram уже привязан к сотруднику \(conflictingName).\nВыберите другой аккаунт или сначала измените привязку у другого сотрудника.",
                replyMarkup: KeyboardBuilder.adminTelegramForwardMenuChange()
            )
            return
        }

        emp.telegramId = fwdId
        emp.isActive = true
        try? await emp.save(on: db)

        try? await PendingLink.query(on: db)
            .filter(\.$employee.$id == empId)
            .delete()

        await TelegramService.sendMessage(
            app, api: api, chatId: chatId,
            text: "✅ Telegram ID обновлен для \(emp.fullName)",
            replyMarkup: KeyboardBuilder.adminTelegramMenu()
        )

        var s = await sessions.get(chatId) ?? Session()
        s.state = .adminTelegramMenu
        s.selectedEmployeeId = nil
        await sessions.set(chatId, s)
    }
}
