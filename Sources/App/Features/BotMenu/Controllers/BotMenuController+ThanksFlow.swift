//
//  BotMenuController+ThanksFlow.swift
//  ChatBot
//

import Vapor
import Fluent

extension BotMenuController {
    
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
        let currentTo = session.to

        switch (state, text) {
        case (.thanksMenu, "Сказать «спасибо»"):
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0)

        case (.thanksMenu, "← Назад"):
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Главное меню:",
                replyMarkup: KeyboardBuilder.mainMenu()
            )
            await sessions.set(chatId, Session(state: .mainMenu))

        case (.thanksMenu, "Статистика"):
            await sessions.set(chatId, Session(state: .statisticsMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Статистика:",
                replyMarkup: KeyboardBuilder.statisticsMenu()
            )
        
        case (.thanksMenu, let t) where isUserAdmin && t.contains("Админ"):
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Админка:",
                replyMarkup: KeyboardBuilder.adminMenu()
            )

        case (.choosingEmployee, "<"), (.choosingEmployee, "⬅"), (.choosingEmployee, "←"), (.choosingEmployee, "⭠"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))

        case (.choosingEmployee, ">"), (.choosingEmployee, "➡"), (.choosingEmployee, "→"), (.choosingEmployee, "⭢"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1)

        case (.choosingEmployee, "← Назад"):
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await sessions.set(chatId, Session(state: .thanksMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isUserAdmin)
            )

        case (.choosingEmployee, _):
            let input = trimmed
            let sel = parseEmployeeSelection(input)
            if let idx = sel.index {
                let candidates = (try? await Employee.query(on: db)
                    .filter(\.$isActive == true)
                    .filter(\.$telegramId != nil)
                    .filter(\.$fullName == sel.name)
                    .all()) ?? []
                
                let sortedCandidates = candidates.sorted { a, b in
                    let aId = (try? a.requireID())?.uuidString ?? ""
                    let bId = (try? b.requireID())?.uuidString ?? ""
                    return aId < bId
                }
                
                if idx >= 1, idx <= sortedCandidates.count,
                   let empId = try? sortedCandidates[idx - 1].requireID() {
                    let emp = sortedCandidates[idx - 1]
                    var senderEmployeeID: UUID? = nil
                    if let tg = userId {
                        senderEmployeeID = try? await Employee.query(on: db)
                            .filter(\.$telegramId == tg)
                            .first()?
                            .requireID()
                    }
                    if let sid = senderEmployeeID, sid == empId {
                        await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
                        await TelegramService.sendMessage(
                            app, api: api, chatId: chatId,
                            text: "Нельзя отправить спасибо самому себе 🙂 Выбери коллегу.",
                            replyMarkup: KeyboardBuilder.backToEmployeesList()
                        )
                        await sessions.set(chatId, Session(state: .choosingEmployee, to: nil, page: (await sessions.get(chatId))?.page))
                        return
                    }
                    let currentPage = (await sessions.get(chatId))?.page
                    await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
                    await sessions.set(chatId, Session(state: .awaitingReason, to: nil, page: currentPage, chosenEmployeeId: empId))
                    await TelegramService.sendMessage(
                        app, api: api, chatId: chatId,
                        text: "Напиши короткое сообщение, за что \(emp.fullName) получит благодарность. 🌟 (от \(minReasonLength) символов)",
                        replyMarkup: KeyboardBuilder.reasonMenu()
                    )
                    return
                }
            }
            
            if let emp = try? await Employee.query(on: db)
                .filter(\.$isActive == true)
                .filter(\.$telegramId != nil)
                .filter(\.$fullName == sel.name)
                .first(),
               let empId = try? emp.requireID() {
                var senderEmployeeID: UUID? = nil
                if let tg = userId {
                    senderEmployeeID = try? await Employee.query(on: db)
                        .filter(\.$telegramId == tg)
                        .first()?
                        .requireID()
                }
                if let sid = senderEmployeeID, sid == empId {
                    await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
                    await TelegramService.sendMessage(
                        app, api: api, chatId: chatId,
                        text: "Нельзя отправить спасибо самому себе 🙂 Выбери коллегу.",
                        replyMarkup: KeyboardBuilder.backToEmployeesList()
                    )
                    await sessions.set(chatId, Session(state: .choosingEmployee, to: nil, page: (await sessions.get(chatId))?.page))
                    return
                }
                let currentPage = (await sessions.get(chatId))?.page
                await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
                await sessions.set(chatId, Session(state: .awaitingReason, to: nil, page: currentPage, chosenEmployeeId: empId))
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Напиши короткое сообщение, за что \(emp.fullName) получит благодарность. 🌟 (от \(minReasonLength) символов)",
                    replyMarkup: KeyboardBuilder.reasonMenu()
                )
            } else {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Не нашел такого сотрудника. Листай </> или выбери из списка."
                )
            }

        case (.awaitingRecipient, "← Назад"):
            await sessions.set(chatId, Session(state: .thanksMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isUserAdmin)
            )

        case (.awaitingRecipient, _) where trimmed.hasPrefix("@"):
            await sessions.set(chatId, Session(state: .awaitingReason, to: trimmed))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Напиши короткое сообщение, за что хочешь сказать «спасибо». 🌟 (от \(minReasonLength) символов)",
                replyMarkup: KeyboardBuilder.reasonMenu()
            )

        case (.awaitingRecipient, _):
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Пришли @username получателя."
            )
            await sessions.set(chatId, Session(state: .awaitingRecipient))

        case (.awaitingReason, "← Назад"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await closeActiveInlineList(app: app, api: api, chatId: chatId, sessions: sessions)
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page)

        case (.awaitingReason, "Отмена"):
            await sessions.set(chatId, Session(state: .mainMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Действие отменено.",
                replyMarkup: KeyboardBuilder.mainMenu()
            )

        case (.awaitingReason, _) where trimmed.count < minReasonLength:
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Сообщение должно содержать не менее \(minReasonLength) символов.",
                replyMarkup: KeyboardBuilder.reasonMenu()
            )
            var s = await sessions.get(chatId) ?? Session()
            s.state = .awaitingReason
            s.to = currentTo
            await sessions.set(chatId, s)

        case (.awaitingReason, _) where trimmed.count >= minReasonLength:
            let fromUN = normalizeUsername(username ?? "unknown")
            let recipientId = (await sessions.get(chatId))?.chosenEmployeeId
            let toUN = currentTo != nil ? normalizeUsername(currentTo!) : "@unknown"

            var senderEmployeeID: UUID? = nil
            if let tg = userId {
                senderEmployeeID = try? await Employee.query(on: db)
                    .filter(\.$telegramId == tg)
                    .first()?
                    .requireID()
            }

            if let sid = senderEmployeeID, let rid = recipientId, sid == rid {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Нельзя отправить спасибо самому себе 🙂 Выберите коллегу.",
                    replyMarkup: KeyboardBuilder.backToEmployeesList()
                )
                let page = (await sessions.get(chatId))?.page ?? 0
                await sessions.set(chatId, Session(state: .choosingEmployee, to: nil, page: page, chosenEmployeeId: nil))
                return
            }

            let kudos = Kudos(
                ts: Date(),
                fromUserId: userId ?? 0,
                fromUsername: fromUN,
                fromName: username ?? fromUN,
                toUsername: toUN,
                reason: trimmed,
                employeeId: recipientId,
                fromEmployeeId: senderEmployeeID
            )
            try? await kudos.save(on: db)
            
            if let rid = recipientId,
               let recipientEmp = try? await Employee.find(rid, on: db),
               let recipientTgId = recipientEmp.telegramId {
                
                var senderDisplayName = username ?? fromUN
                if let uid = userId,
                   let senderEmp = try? await Employee.query(on: db)
                       .filter(\.$telegramId == uid)
                       .first() {
                    senderDisplayName = senderEmp.fullName
                }

                let notifyText = """
                🥳 <b>Тебе прилетело спасибо!</b>
                
                От: \(senderDisplayName)
                Текст: «\(trimmed)»
                """
                
                Task {
                    await TelegramService.sendMessage(app, api: api, chatId: recipientTgId, text: notifyText)
                }
            }

            var targetText = toUN
            if let rid = recipientId, let emp = try? await Employee.find(rid, on: db) {
                targetText = emp.fullName
            }

            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "\(targetText) получил(а) твою благодарность 💛",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isUserAdmin)
            )
            await sessions.set(chatId, Session(state: .thanksMenu, to: nil, page: (await sessions.get(chatId))?.page, chosenEmployeeId: nil))

        default:
            break
        }
    }
}
