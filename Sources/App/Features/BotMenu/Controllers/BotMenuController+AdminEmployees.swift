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
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Настройки:", replyMarkup: KeyboardBuilder.adminMenu())
            } else {
                guard !trimmed.isEmpty else {
                    await TelegramService.sendMessage(
                        app,
                        api: api,
                        chatId: chatId,
                        text: "Имя не может быть пустым. Как подписывать участника?",
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
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Новый участник: \(trimmed.htmlEscaped). Всё верно?", replyMarkup: KeyboardBuilder.yesNo())
            }

        case .adminAddConfirmName:
            if text == "Нет" {
                var session = await sessions.get(chatId) ?? Session()
                session.draftFullName = nil
                session.state = .adminAddAskName
                await sessions.set(chatId, session)
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: Self.askNameText, replyMarkup: KeyboardBuilder.back())
            } else if text == "Да" {
                var session = await sessions.get(chatId) ?? Session()
                session.state = .adminAddAskForward
                await sessions.set(chatId, session)
                await TelegramService.sendMessage(
                    app,
                    api: api,
                    chatId: chatId,
                    text: """
                    Перешли любое сообщение от этого человека, чтобы я узнал его Telegram.

                    <i>Если в пересылках профиль скрыт — нажми кнопку ниже и отправь ему код приглашения.</i>
                    """,
                    replyMarkup: KeyboardBuilder.adminAddForwardMenu()
                )
            }

        case .adminAddAskForward:
            if text == "← Назад" {
                await sessions.set(chatId, Session(state: .adminAddAskName))
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: Self.askNameText, replyMarkup: KeyboardBuilder.back())
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
                Привязываем участника: \(draftName.htmlEscaped)
                к Telegram-аккаунту: \(uname)
                Имя в Telegram: \(tgName.htmlEscaped)
                ID: \(tgId)

                Всё верно?
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

        case .adminEditNameChoose:
            await handleAdminEditNameChoose(app: app, api: api, chatId: chatId, sessions: sessions, db: db, text: text, trimmed: trimmed)

        case .adminEditNameAsk:
            await handleAdminEditNameAsk(app: app, api: api, chatId: chatId, sessions: sessions, db: db, text: text, trimmed: trimmed)

        case .adminEditNameConfirm:
            await handleAdminEditNameConfirm(app: app, api: api, chatId: chatId, sessions: sessions, db: db, text: text)

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
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Участник отключён. Вернуть можно в «📁 Отключённые».", replyMarkup: KeyboardBuilder.adminMenu())
                }
                await sessions.set(chatId, Session(state: .adminMenu))
            } else {
                let s = await sessions.get(chatId)
                if let eid = s?.selectedEmployeeId, let emp = try? await Employee.find(eid, on: db) {
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отключить \(emp.fullName.htmlEscaped)? Бот перестанет ему писать, история сохранится.", replyMarkup: KeyboardBuilder.yesNo())
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
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Участник: \(emp.fullName.htmlEscaped)\nЧто сделать?", replyMarkup: KeyboardBuilder.adminArchiveActionsMenu())
                }
            } else if text == "Да" {
                let s = await sessions.get(chatId)
                let eid = s?.selectedEmployeeId
                if let eid = eid, let emp = try? await Employee.find(eid, on: db) {
                    emp.isActive = true
                    try? await emp.save(on: db)
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Участник снова в боте 💛", replyMarkup: KeyboardBuilder.adminMenu())
                }
                await sessions.set(chatId, Session(state: .adminMenu))
            } else {
                let s = await sessions.get(chatId)
                if let eid = s?.selectedEmployeeId, let emp = try? await Employee.find(eid, on: db) {
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Вернуть \(emp.fullName.htmlEscaped)?", replyMarkup: KeyboardBuilder.yesNo())
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
                let newEmp = Employee(fullName: name, isActive: false)
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
            let pending = PendingLink(code: code, employeeId: empId, createdByAdminTgId: userId, expiresAt: Date().addingTimeInterval(6 * 3600))
            try await pending.save(on: db)
            let msg = """
            Участник <b>\(name.htmlEscaped)</b> добавлен! ✅

            Отправь ему эту команду-приглашение:
            <code>/link \(code)</code>

            Как привязать:
            1) Открыть чат с ботом
            2) Нажать на команду выше (или скопировать) и отправить

            Код действует 6 часов.
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
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Участник \(name.htmlEscaped) добавлен! ✅ Теперь можно говорить друг другу спасибо.", replyMarkup: KeyboardBuilder.adminMenu())
        } catch {
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: \(error.localizedDescription)", replyMarkup: KeyboardBuilder.adminMenu())
        }
        await sessions.set(chatId, Session(state: .adminMenu))
    }

    private static func handleAdminDeactivateChoose(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String, trimmed: String) async {
        if ["<", "⬅", "←", "⭠"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1), active: true, targetState: .adminDeactivateChoose)
        } else if [">", "➡", "→", "⭢"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1, active: true, targetState: .adminDeactivateChoose)
        } else if text == "← Назад" {
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Настройки:", replyMarkup: KeyboardBuilder.adminMenu())
        } else {
            let sel = parseEmployeeSelection(trimmed)
            if let emp = try? await Employee.query(on: db).filter(\.$fullName == sel.name).filter(\.$isActive == true).first(),
               let eid = try? emp.requireID() {
                await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
                var sess = await sessions.get(chatId) ?? Session()
                sess.selectedEmployeeId = eid
                sess.state = .adminDeactivateConfirm
                await sessions.set(chatId, sess)
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отключить \(emp.fullName.htmlEscaped)? Бот перестанет ему писать, история сохранится.", replyMarkup: KeyboardBuilder.yesNo())
            }
        }
    }

    private static func handleAdminEditNameChoose(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String, trimmed: String) async {
        if ["<", "⬅", "←", "⭠"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showAdminEditNameEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))
        } else if [">", "➡", "→", "⭢"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showAdminEditNameEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1)
        } else if text == "← Назад" {
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            var session = await sessions.get(chatId) ?? Session()
            session.state = .adminMenu
            session.selectedEmployeeId = nil
            session.draftFullName = nil
            await sessions.set(chatId, session)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Настройки:", replyMarkup: KeyboardBuilder.adminMenu())
        } else {
            let sel = parseEmployeeSelection(trimmed)
            let candidates = (try? await Employee.query(on: db)
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

            guard let emp = chosen, let empId = try? emp.requireID() else { return }

            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            var session = await sessions.get(chatId) ?? Session()
            session.selectedEmployeeId = empId
            session.draftFullName = nil
            session.state = .adminEditNameAsk
            await sessions.set(chatId, session)

            await TelegramService.sendMessage(
                app,
                api: api,
                chatId: chatId,
                text: "Сейчас: \(emp.fullName.htmlEscaped)\n\nКак теперь подписывать участника?",
                replyMarkup: KeyboardBuilder.back()
            )
        }
    }

    private static func handleAdminEditNameAsk(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String, trimmed: String) async {
        if text == "← Назад" {
            let page = (await sessions.get(chatId))?.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showAdminEditNameEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page)
            return
        }

        guard !trimmed.isEmpty else {
            await TelegramService.sendMessage(
                app,
                api: api,
                chatId: chatId,
                text: "Имя не может быть пустым. Как подписывать участника?",
                replyMarkup: KeyboardBuilder.back()
            )
            return
        }

        guard let session = await sessions.get(chatId),
              let empId = session.selectedEmployeeId,
              let emp = try? await Employee.find(empId, on: db) else {
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Не нашёл этого участника.", replyMarkup: KeyboardBuilder.adminMenu())
            return
        }

        var newSession = session
        newSession.draftFullName = trimmed
        newSession.state = .adminEditNameConfirm
        await sessions.set(chatId, newSession)

        await TelegramService.sendMessage(
            app,
            api: api,
            chatId: chatId,
            text: "Переименовать:\n\(emp.fullName.htmlEscaped) → \(trimmed.htmlEscaped)\n\nВсё верно?",
            replyMarkup: KeyboardBuilder.yesNoCancel()
        )
    }

    private static func handleAdminEditNameConfirm(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String) async {
        if text == "Отмена" {
            var session = await sessions.get(chatId) ?? Session()
            session.state = .adminMenu
            session.selectedEmployeeId = nil
            session.draftFullName = nil
            await sessions.set(chatId, session)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отменено.", replyMarkup: KeyboardBuilder.adminMenu())
            return
        }

        if text == "Нет" {
            var session = await sessions.get(chatId) ?? Session()
            session.state = .adminEditNameAsk
            session.draftFullName = nil
            await sessions.set(chatId, session)
            if let empId = session.selectedEmployeeId, let emp = try? await Employee.find(empId, on: db) {
                await TelegramService.sendMessage(
                    app,
                    api: api,
                    chatId: chatId,
                    text: "Сейчас: \(emp.fullName.htmlEscaped)\n\nКак теперь подписывать участника?",
                    replyMarkup: KeyboardBuilder.back()
                )
            }
            return
        }

        guard text == "Да" else { return }

        guard let session = await sessions.get(chatId),
              let empId = session.selectedEmployeeId,
              let newName = session.draftFullName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !newName.isEmpty,
              let emp = try? await Employee.find(empId, on: db) else {
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Не получилось изменить имя.", replyMarkup: KeyboardBuilder.adminMenu())
            return
        }

        let oldName = emp.fullName
        emp.fullName = newName
        do {
            try await emp.save(on: db)
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "✅ Имя обновлено: \(oldName.htmlEscaped) → \(newName.htmlEscaped)", replyMarkup: KeyboardBuilder.adminMenu())
        } catch {
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка сохранения: \(error.localizedDescription)", replyMarkup: KeyboardBuilder.adminMenu())
        }

        var reset = session
        reset.state = .adminMenu
        reset.selectedEmployeeId = nil
        reset.draftFullName = nil
        await sessions.set(chatId, reset)
    }

    private static func handleAdminArchiveChoose(app: Application, api: String, chatId: Int64, sessions: SessionStore, db: Database, text: String, trimmed: String) async {
        if ["<", "⬅", "←", "⭠"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1), active: false, targetState: .adminArchiveChoose)
        } else if [">", "➡", "→", "⭢"].contains(text) {
            let page = (await sessions.get(chatId))?.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1, active: false, targetState: .adminArchiveChoose)
        } else if text == "← Назад" {
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Настройки:", replyMarkup: KeyboardBuilder.adminMenu())
        } else {
            let sel = parseEmployeeSelection(trimmed)
            if let emp = try? await Employee.query(on: db).filter(\.$fullName == sel.name).filter(\.$isActive == false).first(),
               let eid = try? emp.requireID() {
                await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
                var sess = await sessions.get(chatId) ?? Session()
                sess.selectedEmployeeId = eid
                sess.state = .adminArchiveActions
                await sessions.set(chatId, sess)
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Участник: \(emp.fullName.htmlEscaped)\nЧто сделать?", replyMarkup: KeyboardBuilder.adminArchiveActionsMenu())
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
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Вернуть \(emp.fullName.htmlEscaped)?", replyMarkup: KeyboardBuilder.yesNo())
            }
        } else if text == "🗑 Полное удаление" || text == "🗑 Удалить совсем" {
            let eid = (await sessions.get(chatId))?.selectedEmployeeId
            if let eid = eid, let emp = try? await Employee.find(eid, on: db) {
                let countTo = (try? await Kudos.query(on: db).filter(\.$employee.$id == eid).count()) ?? 0
                let countFrom = (try? await Kudos.query(on: db).filter(\.$fromEmployee.$id == eid).count()) ?? 0
                var sess = await sessions.get(chatId) ?? Session()
                sess.state = .adminArchiveDeleteConfirm
                await sessions.set(chatId, sess)
                let msg = "⚠️ Удалить \(emp.fullName.htmlEscaped) совсем? Вместе с ним удалятся все его спасибо — это нельзя отменить.\nПолучено: \(countTo), отправлено: \(countFrom)"
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
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Участник: \(emp.fullName.htmlEscaped)\nЧто сделать?", replyMarkup: KeyboardBuilder.adminArchiveActionsMenu())
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
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Участник и все его спасибо удалены. 🗑", replyMarkup: KeyboardBuilder.adminMenu())
        } catch {
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: \(error.localizedDescription)", replyMarkup: KeyboardBuilder.adminMenu())
        }
        await sessions.set(chatId, Session(state: .adminMenu))
    }
}
