//
//  BotMenuController+AdminEmployees.swift
//  ChatBot
//

import Vapor
import Fluent

extension BotMenuController {
    
    static func handleAdminEmployeesState(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        username: String?,
        sessions: SessionStore,
        db: Database,
        state: SessionState,
        text: String,
        trimmed: String,
        forwardedFromId: Int64? = nil,
        forwardedFromUsername: String? = nil,
        forwardedFromFirstName: String? = nil,
        forwardedFromLastName: String? = nil
    ) async {
        switch state {
        case .adminAddAskName:
            if text == "← Назад" {
                await sessions.set(chatId, Session(state: .adminMenu))
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Админка:", replyMarkup: KeyboardBuilder.adminMenu())
            } else {
                guard !trimmed.isEmpty else {
                    await TelegramService.sendMessage(
                        app,
                        api: api,
                        chatId: chatId,
                        text: "Ошибка: имя пустое. Введи Фамилию и Имя.",
                        replyMarkup: KeyboardBuilder.back()
                    )
                    var s = await sessions.get(chatId) ?? Session()
                    s.draftFullName = nil
                    s.state = .adminAddAskName
                    await sessions.set(chatId, s)
                    return
                }

                var session = await sessions.get(chatId) ?? Session()
                session.draftFullName = trimmed
                session.state = .adminAddConfirmName
                await sessions.set(chatId, session)
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Новый сотрудник: \(trimmed). Все верно?", replyMarkup: KeyboardBuilder.yesNo())
            }

        case .adminAddConfirmName:
            if text == "Нет" {
                var session = await sessions.get(chatId) ?? Session()
                session.draftFullName = nil
                session.state = .adminAddAskName
                await sessions.set(chatId, session)
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Введи Фамилию и Имя (например: Иванов Иван)", replyMarkup: KeyboardBuilder.back())
            } else if text == "Да" {
                var session = await sessions.get(chatId) ?? Session()
                session.state = .adminAddAskForward
                await sessions.set(chatId, session)
                await TelegramService.sendMessage(
                    app,
                    api: api,
                    chatId: chatId,
                    text: """
                    Перешли любое сообщение от сотрудника, чтобы я мог узнать его Telegram ID.

                    <i>Если у сотрудника скрыт профиль, нажми кнопку ниже для привязки через код.</i>
                    """,
                    replyMarkup: KeyboardBuilder.adminAddForwardMenu()
                )
            }

        case .adminAddAskForward:
            if text == "← Назад" {
                await sessions.set(chatId, Session(state: .adminAddAskName))
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Введи Фамилию и Имя", replyMarkup: KeyboardBuilder.back())
            } else if text == "🔗 Привязать через код" {
                await handleAdminAddLinkByCode(app: app, api: api, chatId: chatId, userId: userId, sessions: sessions, db: db)
            } else {
                // Обработка пересланного сообщения: извлекаем Telegram ID из forward_from
                guard let tgId = forwardedFromId else {
                    await TelegramService.sendMessage(
                        app,
                        api: api,
                        chatId: chatId,
                        text: "Это не пересланное сообщение или профиль скрыт. Попробуй переслать другое сообщение (не от бота, а от человека).",
                        replyMarkup: KeyboardBuilder.adminAddForwardMenu()
                    )
                    return
                }

                let tgName = [forwardedFromFirstName, forwardedFromLastName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let uname = forwardedFromUsername.map { "@\($0)" } ?? "нет логина"

                var session = await sessions.get(chatId) ?? Session()
                session.draftTelegramId = tgId
                session.state = .adminAddConfirmAccount
                await sessions.set(chatId, session)

                let draftName = session.draftFullName ?? "???"
                let msg = """
                Привязываем сотрудника: \(draftName)
                к Telegram-аккаунту: \(uname)
                Имя в Telegram: \(tgName)
                ID: \(tgId)

                Все верно?
                """

                await TelegramService.sendMessage(
                    app,
                    api: api,
                    chatId: chatId,
                    text: msg,
                    replyMarkup: KeyboardBuilder.yesNoCancel()
                )
            }

        case .adminAddConfirmAccount:
            if text == "Нет" {
                var session = await sessions.get(chatId) ?? Session()
                session.state = .adminAddAskForward
                await sessions.set(chatId, session)
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Перешли другое сообщение.", replyMarkup: KeyboardBuilder.adminAddForwardMenu())
            } else if text == "Отмена" {
                await sessions.set(chatId, Session(state: .adminMenu))
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отменено.", replyMarkup: KeyboardBuilder.adminMenu())
            } else if text == "Да" {
                await handleAdminAddConfirmAccountSuccess(app: app, api: api, chatId: chatId, sessions: sessions, db: db)
            }

        case .adminDeactivateChoose:
            await handleAdminDeactivateChoose(app: app, api: api, chatId: chatId, sessions: sessions, db: db, text: text, trimmed: trimmed)

        case .adminDeactivateConfirm:
            if text == "Нет" {
                var s = await sessions.get(chatId) ?? Session()
                s.state = .adminDeactivateChoose
                await sessions.set(chatId, s)
                let page = s.page ?? 0
                await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page, active: true, targetState: .adminDeactivateChoose)
            } else if text == "Да" {
                let s = await sessions.get(chatId)
                let eid = s?.selectedEmployeeId
                if let eid = eid, let emp = try? await Employee.find(eid, on: db) {
                    emp.isActive = false
                    try? await emp.save(on: db)
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник перенесен в архив.", replyMarkup: KeyboardBuilder.adminMenu())
                }
                await sessions.set(chatId, Session(state: .adminMenu))
            } else {
                let s = await sessions.get(chatId)
                if let eid = s?.selectedEmployeeId, let emp = try? await Employee.find(eid, on: db) {
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Деактивировать \(emp.fullName)?", replyMarkup: KeyboardBuilder.yesNo())
                }
            }

        case .adminArchiveChoose:
            await handleAdminArchiveChoose(app: app, api: api, chatId: chatId, sessions: sessions, db: db, text: text, trimmed: trimmed)

        case .adminArchiveActions:
            await handleAdminArchiveActions(app: app, api: api, chatId: chatId, sessions: sessions, db: db, text: text)

        case .adminArchiveConfirm:
            if text == "Нет" {
                var s = await sessions.get(chatId) ?? Session()
                s.state = .adminArchiveActions
                await sessions.set(chatId, s)
                if let eid = s.selectedEmployeeId, let emp = try? await Employee.find(eid, on: db) {
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Выбран сотрудник: \(emp.fullName)\nЧто сделать?", replyMarkup: KeyboardBuilder.adminArchiveActionsMenu())
                }
            } else if text == "Да" {
                let s = await sessions.get(chatId)
                let eid = s?.selectedEmployeeId
                if let eid = eid, let emp = try? await Employee.find(eid, on: db) {
                    emp.isActive = true
                    try? await emp.save(on: db)
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник снова активен.", replyMarkup: KeyboardBuilder.adminMenu())
                }
                await sessions.set(chatId, Session(state: .adminMenu))
            } else {
                let s = await sessions.get(chatId)
                if let eid = s?.selectedEmployeeId, let emp = try? await Employee.find(eid, on: db) {
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Вернуть сотрудника \(emp.fullName)?", replyMarkup: KeyboardBuilder.yesNo())
                }
            }

        case .adminArchiveDeleteConfirm:
            if text == "Нет" {
                await handleAdminArchiveDeleteCancel(app: app, api: api, chatId: chatId, sessions: sessions, db: db)
            } else if text == "Да" {
                await handleAdminArchiveDeleteConfirmSuccess(app: app, api: api, chatId: chatId, userId: userId, username: username, sessions: sessions, db: db)
            }

        default:
            break
        }
    }
    
    // Internal helpers for this extension
    
    private static func handleAdminAddLinkByCode(app: Application, api: String, chatId: Int64, userId: Int64?, sessions: SessionStore, db: Database) async {
        guard let session = await sessions.get(chatId), let draftName = session.draftFullName else {
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сессия потеряна.", replyMarkup: KeyboardBuilder.adminMenu())
            await sessions.set(chatId, Session(state: .adminMenu))
            return
        }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let existing = try await Employee.query(on: db)
                .filter(\.$fullName == name)
                .filter(\.$telegramId == nil)
                .filter(\.$isActive == true)
                .first()
            let emp: Employee
            if let existing { emp = existing } else {
                let newEmp = Employee(fullName: name, isActive: true)
                try await newEmp.save(on: db)
                emp = newEmp
            }
            let empId = try emp.requireID()
            var code = ""
            var success = false
            for _ in 1...5 {
                let randomCode = String(Int.random(in: 100000...999999))
                if try await PendingLink.query(on: db).filter(\.$code == randomCode).first() == nil {
                    code = randomCode
                    success = true
                    break
                }
            }
            guard success else { return }
            let pending = PendingLink(code: code, employeeId: empId, createdByAdminTgId: userId, expiresAt: Date().addingTimeInterval(15 * 60))
            try await pending.save(on: db)
            let msg = """
            Сотрудник <b>\(name)</b> создан! ✅

            Отправь сотруднику эту команду для привязки Telegram:
            <code>/link \(code)</code>

            Как привязать:
            1) Открыть чат с ботом
            2) Нажать на команду выше (или скопировать) и отправить

            Код действует 15 минут.
            """
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg, replyMarkup: KeyboardBuilder.adminMenu())
            await sessions.set(chatId, Session(state: .adminMenu))
        } catch {
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: \(error.localizedDescription)", replyMarkup: KeyboardBuilder.adminMenu())
            await sessions.set(chatId, Session(state: .adminMenu))
        }
    }

    private static func handleAdminAddConfirmAccountSuccess(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database) async {
        guard let session = await sessions.get(chatId), let tgId = session.draftTelegramId, let rawName = session.draftFullName else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newEmp = Employee(fullName: name, isActive: true)
        newEmp.telegramId = tgId
        do {
            try await newEmp.save(on: db)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник \(name) добавлен! ✅", replyMarkup: KeyboardBuilder.adminMenu())
        } catch {
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: \(error.localizedDescription)", replyMarkup: KeyboardBuilder.adminMenu())
        }
        await sessions.set(chatId, Session(state: .adminMenu))
    }

    private static func handleAdminDeactivateChoose(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String, trimmed: String) async {
        if ["<", "⬅", "←", "⭠"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1), active: true, targetState: .adminDeactivateChoose)
        } else if [">", "➡", "→", "⭢"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1, active: true, targetState: .adminDeactivateChoose)
        } else if text == "← Назад" {
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Админка:", replyMarkup: KeyboardBuilder.adminMenu())
        } else {
            let sel = parseEmployeeSelection(trimmed)
            if let emp = try? await Employee.query(on: db).filter(\.$fullName == sel.name).filter(\.$isActive == true).first(),
               let eid = try? emp.requireID() {
                var sess = await sessions.get(chatId) ?? Session()
                sess.selectedEmployeeId = eid
                sess.state = .adminDeactivateConfirm
                await sessions.set(chatId, sess)
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Деактивировать \(emp.fullName)?", replyMarkup: KeyboardBuilder.yesNo())
            }
        }
    }

    private static func handleAdminArchiveChoose(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String, trimmed: String) async {
        if ["<", "⬅", "←", "⭠"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1), active: false, targetState: .adminArchiveChoose)
        } else if [">", "➡", "→", "⭢"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1, active: false, targetState: .adminArchiveChoose)
        } else if text == "← Назад" {
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Админка:", replyMarkup: KeyboardBuilder.adminMenu())
        } else {
            let sel = parseEmployeeSelection(trimmed)
            if let emp = try? await Employee.query(on: db).filter(\.$fullName == sel.name).filter(\.$isActive == false).first(),
               let eid = try? emp.requireID() {
                var sess = await sessions.get(chatId) ?? Session()
                sess.selectedEmployeeId = eid
                sess.state = .adminArchiveActions
                await sessions.set(chatId, sess)
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Выбран сотрудник: \(emp.fullName)\nЧто сделать?", replyMarkup: KeyboardBuilder.adminArchiveActionsMenu())
            }
        }
    }

    private static func handleAdminArchiveActions(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String) async {
        if text == "✅ Восстановить" {
            let eid = (await sessions.get(chatId))?.selectedEmployeeId
            if let eid = eid, let emp = try? await Employee.find(eid, on: db) {
                var sess = await sessions.get(chatId) ?? Session()
                sess.state = .adminArchiveConfirm
                await sessions.set(chatId, sess)
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Вернуть сотрудника \(emp.fullName)?", replyMarkup: KeyboardBuilder.yesNo())
            }
        } else if text == "🗑 Полное удаление" || text == "🗑 Удалить из системы" {
            let eid = (await sessions.get(chatId))?.selectedEmployeeId
            if let eid = eid, let emp = try? await Employee.find(eid, on: db) {
                let countTo = (try? await Kudos.query(on: db).filter(\.$employee.$id == eid).count()) ?? 0
                let countFrom = (try? await Kudos.query(on: db).filter(\.$fromEmployee.$id == eid).count()) ?? 0
                var sess = await sessions.get(chatId) ?? Session()
                sess.state = .adminArchiveDeleteConfirm
                await sessions.set(chatId, sess)
                let msg = "⚠️ ВНИМАНИЕ! Удалить \(emp.fullName)?\nПолучено: \(countTo), Отправлено: \(countFrom)"
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg, replyMarkup: KeyboardBuilder.yesNo())
            }
        } else if text == "← Назад" {
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page, active: false, targetState: .adminArchiveChoose)
        }
    }

    private static func handleAdminArchiveDeleteCancel(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database) async {
        let sess = await sessions.get(chatId) ?? Session()
        if let eid = sess.selectedEmployeeId, let emp = try? await Employee.find(eid, on: db) {
            var newSess = sess
            newSess.state = .adminArchiveActions
            await sessions.set(chatId, newSess)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Выбран сотрудник: \(emp.fullName)\nЧто сделать?", replyMarkup: KeyboardBuilder.adminArchiveActionsMenu())
        } else {
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отменено.", replyMarkup: KeyboardBuilder.adminMenu())
        }
    }

    private static func handleAdminArchiveDeleteConfirmSuccess(app: Application, api: String, chatId: Int64, userId: Int64?, username: String?, sessions: SessionStore, db: Database) async {
        guard let sess = await sessions.get(chatId), let eid = sess.selectedEmployeeId else { return }
        do {
            try await db.transaction { tx in
                try await Kudos.query(on: tx).group(.or) { or in
                    or.filter(\.$employee.$id == eid)
                    or.filter(\.$fromEmployee.$id == eid)
                }.delete()
                if let emp = try await Employee.find(eid, on: tx) { try await emp.delete(on: tx) }
            }
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник и все его благодарности полностью удалены из системы. 🗑✅", replyMarkup: KeyboardBuilder.adminMenu())
        } catch {
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: \(error.localizedDescription)", replyMarkup: KeyboardBuilder.adminMenu())
        }
        await sessions.set(chatId, Session(state: .adminMenu))
    }
}
