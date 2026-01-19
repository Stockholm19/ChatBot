//
//  BotMenuController.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 25.09.2025.
//

import Vapor
import Fluent

enum BotMenuController {

    // Минимальная длина текста благодарности
    private static let minReasonLength = 20

     // MARK: - Helpers
     
     /// Нормализует ник: trim + lowercased + ensure leading '@'
     private static func normalizeUsername(_ raw: String) -> String {
         let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
         if t.isEmpty { return "@unknown" }
         return t.hasPrefix("@") ? t : "@\(t)"
     }
     
     /// Возвращает срез массива для страницы `page` (0-based) по `per` элементов
     private static func pageSlice<T>(_ items: [T], page: Int, per: Int = 10) -> ArraySlice<T> {
         let start = max(0, page * per)
         let end = min(items.count, start + per)
         return items[start..<end]
     }
     
     /// Парсит выбор сотрудника из текста кнопки.
     /// Поддерживает формат "ФИО (N)" только для случаев, когда есть дубли ФИО.
     /// Возвращает базовое ФИО и порядковый номер (1-based), если он указан.
     private static func parseEmployeeSelection(_ text: String) -> (name: String, index: Int?) {
         let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
         guard t.hasSuffix(")"), let open = t.lastIndex(of: "(") else {
             return (t, nil)
         }
         let inside = t[t.index(after: open)..<t.index(before: t.endIndex)]
         let numStr = inside.trimmingCharacters(in: .whitespacesAndNewlines)
         guard let n = Int(numStr), n > 0 else {
             return (t, nil)
         }
         let base = t[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
         return (String(base), n)
     }
    
     /// Показывает страницу каталога сотрудников
     private static func showEmployeesPage(
         app: Application,
         api: String,
         chatId: Int64,
         sessions: SessionStore,
         db: Database,
         page: Int
     ) async {
         let all = (try? await Employee.query(on: db)
             .filter(\.$isActive == true)
             .sort(\.$fullName, .ascending)
             .all()) ?? []
         
         let per = 10
         let totalPages = max(1, Int(ceil(Double(all.count) / Double(per))))
         let p = max(0, min(page, totalPages - 1))
         let slice = pageSlice(all, page: p, per: per)
         // Формируем подписи кнопок. Суффикс "(N)" добавляем только если есть дубли ФИО.
         var titleById: [UUID: String] = [:]
         let groups = Dictionary(grouping: all, by: { $0.fullName })
         for (name, emps) in groups {
             if emps.count == 1, let id = try? emps[0].requireID() {
                 titleById[id] = name
             } else {
                 let sorted = emps.sorted { a, b in
                     let aId = (try? a.requireID())?.uuidString ?? ""
                     let bId = (try? b.requireID())?.uuidString ?? ""
                     return aId < bId
                 }
                 for (i, emp) in sorted.enumerated() {
                     if let id = try? emp.requireID() {
                         titleById[id] = "\(name) (\(i + 1))"
                     }
                 }
             }
         }

         let titles = Array(slice.map { emp -> String in
             guard let id = try? emp.requireID() else { return emp.fullName }
             return titleById[id] ?? emp.fullName
         })
         
         await TelegramService.sendMessage(
             app, api: api, chatId: chatId,
             text: "Кому сказать спасибо?",
             replyMarkup: KeyboardBuilder.employeesPage(
                 names: titles,
                 hasPrev: p > 0,
                 hasNext: p < totalPages - 1
             )
         )
         await sessions.set(chatId, Session(state: .choosingEmployee, page: p))
     }

     /// Показывает страницу сотрудников (активных или архивных) для админа
     private static func showAdminEmployeesPage(
         app: Application,
         api: String,
         chatId: Int64,
         sessions: SessionStore,
         db: Database,
         page: Int,
         active: Bool,
         targetState: SessionState
     ) async {
         let all = (try? await Employee.query(on: db)
             .filter(\.$isActive == active)
             .sort(\.$fullName, .ascending)
             .all()) ?? []
         
         let per = 10
         let totalPages = max(1, Int(ceil(Double(all.count) / Double(per))))
         let p = max(0, min(page, totalPages - 1))
         let slice = pageSlice(all, page: p, per: per)
         // Формируем подписи кнопок. Суффикс "(N)" добавляем только если есть дубли ФИО.
         var titleById: [UUID: String] = [:]
         let groups = Dictionary(grouping: all, by: { $0.fullName })
         for (name, emps) in groups {
             if emps.count == 1, let id = try? emps[0].requireID() {
                 titleById[id] = name
             } else {
                 let sorted = emps.sorted { a, b in
                     let aId = (try? a.requireID())?.uuidString ?? ""
                     let bId = (try? b.requireID())?.uuidString ?? ""
                     return aId < bId
                 }
                 for (i, emp) in sorted.enumerated() {
                     if let id = try? emp.requireID() {
                         titleById[id] = "\(name) (\(i + 1))"
                     }
                 }
             }
         }

         let titles = Array(slice.map { emp -> String in
             guard let id = try? emp.requireID() else { return emp.fullName }
             return titleById[id] ?? emp.fullName
         })
         
         let title = active ? "Кого деактивировать?" : "Кого вернуть из архива?"
         
         await TelegramService.sendMessage(
             app, api: api, chatId: chatId,
             text: title,
             replyMarkup: KeyboardBuilder.employeesPage(
                 names: titles,
                 hasPrev: p > 0,
                 hasNext: p < totalPages - 1
             )
         )
         // Сохраняем стейт, но возможно нужно не терять другие поля.
         // Но при навигации они обычно не нужны.
         var session = await sessions.get(chatId) ?? Session()
         session.state = targetState
         session.page = p
         await sessions.set(chatId, session)
     }

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
        sessions: SessionStore
    ) async {
            // Игнорируем группы и каналы: бот показывает меню только в личных чатах
            if chatId <= 0 {
                return
            }

            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: """
                Привет! 👋

                С помощью этого бота ты можешь отправить благодарность коллеге — за поддержку, классные идеи или просто за хорошую работу. А еще здесь можно увидеть, сколько «спасибо» получил лично ты.

                Выбери действие:
                """,
                replyMarkup: KeyboardBuilder.mainMenu()
            )
            await sessions.set(chatId, Session(state: .mainMenu, to: nil))
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
        let currentTo = session.to
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = trimmed.normalizedNav
        
        let isUserAdmin = isAdmin(userId: userId, username: username)
        app.logger.info("BotMenu: state=\(state), text='\(t)', isAdmin=\(isUserAdmin)")

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

        switch (state, t) {
        // Глобальная обработка возврата к списку сотрудников
        case (_, "← Назад к списку"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page)
            return
        // MARK: - Каталог сотрудников: навигация и выбор
        case (.choosingEmployee, "<"), (.choosingEmployee, "⬅"), (.choosingEmployee, "←"), (.choosingEmployee, "⭠"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))
            return

        case (.choosingEmployee, ">"), (.choosingEmployee, "➡"), (.choosingEmployee, "→"), (.choosingEmployee, "⭢"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1)
            return

//   Скрый ручной ввод пользователя по нику
            
//        case (.choosingEmployee, "Ввести @username вручную"):
//            await sessions.set(chatId, Session(state: .awaitingRecipient))
//            await TelegramService.sendMessage(
//                app, api: api, chatId: chatId,
//                text: "Пришли @username получателя.",
//                replyMarkup: KeyboardBuilder.chooseRecipientMenu()
//            )
//            return

        case (.choosingEmployee, "← Назад"):
            await sessions.set(chatId, Session(state: .thanksMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
            )
            return

         // Любой другой текст на этом шаге считаем выбором сотрудника по ФИО
         case (.choosingEmployee, _):
             let input = trimmed
             let sel = parseEmployeeSelection(input)
             if let idx = sel.index {
                 let candidates = (try? await Employee.query(on: db)
                     .filter(\.$isActive == true)
                     .filter(\.$fullName == sel.name)
                     .sort(\.$id, .ascending)
                     .all()) ?? []
                 if idx >= 1, idx <= candidates.count,
                    let empId = try? candidates[idx - 1].requireID() {
                     let emp = candidates[idx - 1]
                     // запрет "самому себе" на этапе выбора
                     var senderEmployeeID: UUID? = nil
                     if let tg = userId {
                         senderEmployeeID = try? await Employee.query(on: db)
                             .filter(\.$telegramId == tg)
                             .first()?
                             .requireID()
                     }
                     if let sid = senderEmployeeID, sid == empId {
                         await TelegramService.sendMessage(
                             app, api: api, chatId: chatId,
                             text: "Нельзя отправить спасибо самому себе 🙂 Выбери коллегу.",
                             replyMarkup: KeyboardBuilder.backToEmployeesList()
                         )
                         await sessions.set(chatId, Session(state: .choosingEmployee, to: nil, page: (await sessions.get(chatId))?.page))
                         app.logger.info("self_kudos_blocked ui tg:\(userId.map(String.init) ?? "nil")")
                         return
                     }
                     // Preserve the current page when transitioning to awaitingReason
                     let currentPage = (await sessions.get(chatId))?.page
                     await sessions.set(chatId, Session(state: .awaitingReason, to: nil, page: currentPage, chosenEmployeeId: empId))
                     await TelegramService.sendMessage(
                         app, api: api, chatId: chatId,
                         text: "Напиши короткое сообщение, за что \(emp.fullName) получит благодарность. 🌟 (от \(minReasonLength) символов)",
                         replyMarkup: KeyboardBuilder.reasonMenu()
                     )
                     return
                 } else {
                     await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Не нашел такого сотрудника. Листай </> или выбери из списка.")
                     return
                 }
             }
             // Fallback: ищем по полному ФИО (для старых сообщений или ручного ввода)
             if let emp = try? await Employee.query(on: db)
                 .filter(\.$isActive == true)
                 .filter(\.$fullName == sel.name)
                 .first(),
                let empId = try? emp.requireID() {
                 // запрет "самому себе" на этапе выбора
                 var senderEmployeeID: UUID? = nil
                 if let tg = userId {
                     senderEmployeeID = try? await Employee.query(on: db)
                         .filter(\.$telegramId == tg)
                         .first()?
                         .requireID()
                 }
                 if let sid = senderEmployeeID, sid == empId {
                     await TelegramService.sendMessage(
                         app, api: api, chatId: chatId,
                         text: "Нельзя отправить спасибо самому себе 🙂 Выбери коллегу.",
                         replyMarkup: KeyboardBuilder.backToEmployeesList()
                     )
                     await sessions.set(chatId, Session(state: .choosingEmployee, to: nil, page: (await sessions.get(chatId))?.page))
                     app.logger.info("self_kudos_blocked ui tg:\(userId.map(String.init) ?? "nil")")
                     return
                 }
                 // Preserve the current page when transitioning to awaitingReason
                 let currentPage = (await sessions.get(chatId))?.page
                 await sessions.set(chatId, Session(state: .awaitingReason, to: nil, page: currentPage, chosenEmployeeId: empId))
                 await TelegramService.sendMessage(
                     app, api: api, chatId: chatId,
                     text: "Напиши короткое сообщение, за что \(emp.fullName) получит благодарность. 🌟 (от \(minReasonLength) символов)",
                     replyMarkup: KeyboardBuilder.reasonMenu()
                 )
                 return
             } else {
                 await TelegramService.sendMessage(
                     app, api: api, chatId: chatId,
                     text: "Не нашёл такого сотрудника. Листай </> или выбери из списка."
                 )
                 return
             }

        // MARK: Главное меню → подменю «Спасибо»
        case (.mainMenu, "Передать спасибо"):
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
            )
            await sessions.set(chatId, Session(state: .thanksMenu, to: nil))
            return

        // MARK: Подменю «Спасибо» — запустить сценарий
        case (.thanksMenu, "Сказать «спасибо»"):
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0)
            return


        case (.thanksMenu, "Статистика"):
            await sessions.set(chatId, Session(state: .statisticsMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Статистика:",
                replyMarkup: KeyboardBuilder.statisticsMenu()
            )
            return

        case (.statisticsMenu, "← Назад"):
            await sessions.set(chatId, Session(state: .thanksMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
            )
            return

        case (.statisticsMenu, "Моя статистика"):
            var sentTotal = 0
            var receivedTotal = 0
            if let tg = userId,
               let me = try? await Employee.query(on: db)
                   .filter(\.$telegramId == tg)
                   .first(),
               let meID = try? me.requireID() {

                sentTotal = (try? await Kudos.query(on: db)
                    .filter(\.$fromEmployee.$id == meID)
                    .count()) ?? 0

                receivedTotal = (try? await Kudos.query(on: db)
                    .filter(\.$employee.$id == meID)
                    .count()) ?? 0
            }
            let msg = "Твоя статистика:\nОтправлено: \(sentTotal)\nПолучено: \(receivedTotal)"
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: msg,
                replyMarkup: KeyboardBuilder.statisticsMenu()
            )
            return

        case (.statisticsMenu, "Экспорт переданных"):
            app.logger.info("BotMenu: user requested personal export of sent kudos")

            var rows: [Kudos] = []

            // 1. Пробуем найти сотрудника по telegram_id и использовать FK
            if let tg = userId,
               let me = try? await Employee.query(on: db)
                   .filter(\.$telegramId == tg)
                   .first(),
               let meID = try? me.requireID() {

                rows = (try? await Kudos.query(on: db)
                    .filter(\.$fromEmployee.$id == meID)
                    .sort(\.$ts, .descending)
                    .all()) ?? []
            }

            // 2. Fallback по username (на случай отсутствия привязки к сотруднику)
            if rows.isEmpty {
                let raw = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !raw.isEmpty {
                    let withAt = raw.hasPrefix("@") ? raw : "@\(raw)"
                    rows = (try? await Kudos.query(on: db)
                        .group(.or) { or in
                            or.filter(\.$fromUsername == withAt)
                            or.filter(\.$fromUsername == raw)
                        }
                        .sort(\.$ts, .descending)
                        .all()) ?? []
                }
            }

            if rows.isEmpty {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "У тебя пока нет отправленных «спасибо» для экспорта.",
                    replyMarkup: KeyboardBuilder.statisticsMenu()
                )
                return
            }

            let uniqueFilename = "kudos_sent_\(UUID().uuidString).csv"
            let tmpPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(uniqueFilename).path

            defer {
                do {
                    try FileManager.default.removeItem(atPath: tmpPath)
                    app.logger.info("Cleaned up personal sent CSV: \(tmpPath)")
                } catch {
                    app.logger.warning("Failed to clean up personal sent CSV: \(tmpPath). Error: \(error)")
                }
            }

            do {
                try await CSVExporter.exportKudos(db: db, rows: rows, to: tmpPath)
                try await TelegramService.sendDocument(
                    app, api: api, chatId: chatId,
                    filePath: tmpPath,
                    caption: "Экспорт отправленных благодарностей"
                )
            } catch {
                app.logger.error("Failed to export or send personal sent CSV: \(error)")
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Не получилось создать или отправить экспорт отправленных благодарностей.",
                    replyMarkup: KeyboardBuilder.statisticsMenu()
                )
            }
            return

        case (.statisticsMenu, "Экспорт полученных"):
            app.logger.info("BotMenu: user requested personal export of received kudos")

            var rows: [Kudos] = []

            // 1. Пробуем найти сотрудника по telegram_id и использовать FK
            if let tg = userId,
               let me = try? await Employee.query(on: db)
                   .filter(\.$telegramId == tg)
                   .first(),
               let meID = try? me.requireID() {

                rows = (try? await Kudos.query(on: db)
                    .filter(\.$employee.$id == meID)
                    .sort(\.$ts, .descending)
                    .all()) ?? []
            }

            // 2. Fallback по username (на случай отсутствия привязки к сотруднику)
            if rows.isEmpty {
                let raw = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !raw.isEmpty {
                    let withAt = raw.hasPrefix("@") ? raw : "@\(raw)"
                    rows = (try? await Kudos.query(on: db)
                        .group(.or) { or in
                            or.filter(\.$toUsername == withAt)
                            or.filter(\.$toUsername == raw)
                        }
                        .sort(\.$ts, .descending)
                        .all()) ?? []
                }
            }

            if rows.isEmpty {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "У тебя пока нет полученных «спасибо» для экспорта.",
                    replyMarkup: KeyboardBuilder.statisticsMenu()
                )
                return
            }

            let uniqueFilename = "kudos_received_\(UUID().uuidString).csv"
            let tmpPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(uniqueFilename).path

            defer {
                do {
                    try FileManager.default.removeItem(atPath: tmpPath)
                    app.logger.info("Cleaned up personal received CSV: \(tmpPath)")
                } catch {
                    app.logger.warning("Failed to clean up personal received CSV: \(tmpPath). Error: \(error)")
                }
            }

            do {
                try await CSVExporter.exportKudos(db: db, rows: rows, to: tmpPath)
                try await TelegramService.sendDocument(
                    app, api: api, chatId: chatId,
                    filePath: tmpPath,
                    caption: "Экспорт полученных благодарностей"
                )
            } catch {
                app.logger.error("Failed to export or send personal received CSV: \(error)")
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Не получилось создать или отправить экспорт полученных благодарностей.",
                    replyMarkup: KeyboardBuilder.statisticsMenu()
                )
            }
            return

        case (.thanksMenu, "Админка") where isAdmin(userId: userId, username: username):
            await sessions.set(chatId, Session(state: .adminMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Раздел администратора:",
                replyMarkup: KeyboardBuilder.adminMenu()
            )
            return

        case (.adminMenu, "📊 Экспорт CSV") where isAdmin(userId: userId, username: username):

            // Генерируем уникальное имя файла для каждого запроса
            let uniqueFilename = "kudos_export_\(UUID().uuidString).csv"
            let tmpPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(uniqueFilename).path

            // Используем 'defer' для гарантированной очистки файла после использования
            defer {
                do {
                    try FileManager.default.removeItem(atPath: tmpPath)
                    app.logger.info("Successfully cleaned up temporary file: \(tmpPath)")
                } catch {
                    app.logger.warning("Failed to clean up temporary file: \(tmpPath). Error: \(error)")
                }
            }
            
            do {
                try await CSVExporter.exportKudos(db: db, to: tmpPath)
                try await TelegramService.sendDocument(
                    app, api: api, chatId: chatId,
                    filePath: tmpPath,
                    caption: "Экспорт благодарностей"
                )
            } catch {
                app.logger.error("Failed to export or send CSV: \(error)")
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Не удалось создать или отправить экспорт. Пожалуйста, проверьте логи.")
            }
            return

        case (_, let cmd) where cmd.contains("Добавить сотрудника") && isAdmin(userId: userId, username: username):
            await sessions.set(chatId, Session(state: .adminAddAskName))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Введи Фамилию и Имя (например: Иванов Иван)",
                replyMarkup: KeyboardBuilder.back()
            )
            return
            
        case (_, let cmd) where cmd.contains("Деактивировать сотрудника") && isAdmin(userId: userId, username: username):
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0, active: true, targetState: .adminDeactivateChoose)
            return
            
        case (_, let cmd) where cmd.contains("Архив сотрудников") && isAdmin(userId: userId, username: username):
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0, active: false, targetState: .adminArchiveChoose)
            return
            


        case (.adminMenu, "← Назад"):
            await sessions.set(chatId, Session(state: .thanksMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
            )
            return

        // MARK: - Admin Flow: Add Employee
        
        case (.adminAddAskName, "← Назад"):
             await sessions.set(chatId, Session(state: .adminMenu))
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Раздел администратора:", replyMarkup: KeyboardBuilder.adminMenu())
             return

        case (.adminAddAskName, _):
             // Save draft name
             var session = await sessions.get(chatId) ?? Session()
             session.draftFullName = trimmed
             session.state = .adminAddConfirmName
             await sessions.set(chatId, session)
             
             await TelegramService.sendMessage(
                 app, api: api, chatId: chatId,
                 text: "Новый сотрудник: \(trimmed). Все верно?",
                 replyMarkup: KeyboardBuilder.yesNo()
             )
             return

        case (.adminAddConfirmName, "Нет"):
             // Clear draft and ask again
             var session = await sessions.get(chatId) ?? Session()
             session.draftFullName = nil
             session.state = .adminAddAskName
             await sessions.set(chatId, session)
             
             await TelegramService.sendMessage(
                 app, api: api, chatId: chatId,
                 text: "Введи Фамилию и Имя (например: Иванов Иван)",
                 replyMarkup: KeyboardBuilder.back()
             )
             return

        case (.adminAddConfirmName, "Да"):
             // Next step: ask forward
             var session = await sessions.get(chatId) ?? Session()
             session.state = .adminAddAskForward
             await sessions.set(chatId, session)
             
             await TelegramService.sendMessage(
                 app, api: api, chatId: chatId,
                 text: "Перешли любое сообщение от сотрудника, чтобы я мог узнать его Telegram ID.",
                 replyMarkup: KeyboardBuilder.back()
             )
             return
        
        case (.adminAddAskForward, "← Назад"):
             // Back to start of add flow
             await sessions.set(chatId, Session(state: .adminAddAskName))
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Введи Фамилию и Имя", replyMarkup: KeyboardBuilder.back())
             return

        case (.adminAddAskForward, _):
             // Check forward
             guard let fwd = message.forward_from else {
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Это не пересланное сообщение или профиль скрыт. Попробуй переслать другое сообщение (не от бота, а от человека).")
                 return
             }
             
             let tgId = fwd.id
             let tgName = [fwd.first_name, fwd.last_name].compactMap { $0 }.joined(separator: " ")
             let username = fwd.username.map { "@\($0)" } ?? "нет логина"
             
             // Check if already exists? (Optional but good)
             
             var session = await sessions.get(chatId) ?? Session()
             session.draftTelegramId = tgId
             session.state = .adminAddConfirmAccount
             await sessions.set(chatId, session)
             
             let draftName = session.draftFullName ?? "???"
             let msg = """
             Привязываем сотрудника: \(draftName)
             к Telegram-аккаунту: \(username)
             Имя в Telegram: \(tgName)
             ID: \(tgId)
             
             Все верно?
             """
             
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg, replyMarkup: KeyboardBuilder.yesNoCancel())
             return

        case (.adminAddConfirmAccount, "Нет"):
             // Back to forward
             var session = await sessions.get(chatId) ?? Session()
             session.state = .adminAddAskForward
             await sessions.set(chatId, session)
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Перешли другое сообщение.", replyMarkup: KeyboardBuilder.back())
             return
             
        case (.adminAddConfirmAccount, "Отмена"):
              await sessions.set(chatId, Session(state: .adminMenu))
              await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отменено.", replyMarkup: KeyboardBuilder.adminMenu())
              return

         case (.adminAddConfirmAccount, "Да"):
                // Validate telegramId and fullName before creating employee
                guard let session = await sessions.get(chatId),
                      let tgId = session.draftTelegramId,
                      let rawName = session.draftFullName else {
                    await TelegramService.sendMessage(
                        app, api: api, chatId: chatId,
                        text: "Ошибка: не удалось получить имя или Telegram ID. Начни добавление заново.",
                        replyMarkup: KeyboardBuilder.adminMenu()
                    )
                    await sessions.set(chatId, Session(state: .adminMenu))
                    return
                }
                 
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    await TelegramService.sendMessage(
                        app, api: api, chatId: chatId,
                        text: "Ошибка: имя пустое. Введи Фамилию и Имя.",
                        replyMarkup: KeyboardBuilder.adminMenu()
                    )
                    await sessions.set(chatId, Session(state: .adminMenu))
                    return
                }
                 
                let newEmp = Employee(fullName: name, isActive: true)
                newEmp.telegramId = tgId
                 
                do {
                    try await newEmp.save(on: db)
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник \(name) добавлен! ✅", replyMarkup: KeyboardBuilder.adminMenu())
                } catch {
                    app.logger.error("Failed to add employee: \(error)")
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка при сохранении: \(error.localizedDescription)", replyMarkup: KeyboardBuilder.adminMenu())
                }
                await sessions.set(chatId, Session(state: .adminMenu))
                return


        // MARK: - Admin Flow: Deactivate

        case (.adminDeactivateChoose, "<"), (.adminDeactivateChoose, "⬅"), (.adminDeactivateChoose, "←"), (.adminDeactivateChoose, "⭠"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1), active: true, targetState: .adminDeactivateChoose)
            return

        case (.adminDeactivateChoose, ">"), (.adminDeactivateChoose, "➡"), (.adminDeactivateChoose, "→"), (.adminDeactivateChoose, "⭢"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1, active: true, targetState: .adminDeactivateChoose)
            return
            
        case (.adminDeactivateChoose, "← Назад"):
             await sessions.set(chatId, Session(state: .adminMenu))
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Админка:", replyMarkup: KeyboardBuilder.adminMenu())
             return

         case (.adminDeactivateChoose, _):
              let input = trimmed
              let sel = parseEmployeeSelection(input)
              if let idx = sel.index {
                  let candidates = (try? await Employee.query(on: db)
                      .filter(\.$isActive == true)
                      .filter(\.$fullName == sel.name)
                      .sort(\.$id, .ascending)
                      .all()) ?? []
                  if idx >= 1, idx <= candidates.count,
                     let eid = try? candidates[idx - 1].requireID() {
                      let emp = candidates[idx - 1]
                      var sess = await sessions.get(chatId) ?? Session()
                      sess.selectedEmployeeId = eid
                      sess.state = .adminDeactivateConfirm
                      await sessions.set(chatId, sess)
                      await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Деактивировать \(emp.fullName)?", replyMarkup: KeyboardBuilder.yesNo())
                      return
                  } else {
                      await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник не найден.")
                      return
                  }
              }
              // Fallback: ищем по полному ФИО
              if let emp = try? await Employee.query(on: db).filter(\.$fullName == sel.name).filter(\.$isActive == true).first(),
                 let eid = try? emp.requireID() {
                  var sess = await sessions.get(chatId) ?? Session()
                  sess.selectedEmployeeId = eid
                  sess.state = .adminDeactivateConfirm
                  await sessions.set(chatId, sess)
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Деактивировать \(emp.fullName)?", replyMarkup: KeyboardBuilder.yesNo())
              } else {
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник не найден.")
              }
              return

        case (.adminDeactivateConfirm, "Нет"):
             await sessions.set(chatId, Session(state: .adminMenu))
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отменено.", replyMarkup: KeyboardBuilder.adminMenu())
             return

        case (.adminDeactivateConfirm, "Да"):
             let eid = (await sessions.get(chatId))?.selectedEmployeeId
             if let eid = eid, let emp = try? await Employee.find(eid, on: db) {
                 emp.isActive = false
                 try? await emp.save(on: db)
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник перенесен в архив.", replyMarkup: KeyboardBuilder.adminMenu())
             } else {
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сотрудник не найден.", replyMarkup: KeyboardBuilder.adminMenu())
             }
             await sessions.set(chatId, Session(state: .adminMenu))
             return

        // MARK: - Admin Flow: RESTORE (Archive)
        
        case (.adminArchiveChoose, "<"), (.adminArchiveChoose, "⬅"), (.adminArchiveChoose, "←"), (.adminArchiveChoose, "⭠"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1), active: false, targetState: .adminArchiveChoose)
            return

        case (.adminArchiveChoose, ">"), (.adminArchiveChoose, "➡"), (.adminArchiveChoose, "→"), (.adminArchiveChoose, "⭢"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1, active: false, targetState: .adminArchiveChoose)
            return
            
        case (.adminArchiveChoose, "← Назад"):
             await sessions.set(chatId, Session(state: .adminMenu))
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Админка:", replyMarkup: KeyboardBuilder.adminMenu())
             return

         case (.adminArchiveChoose, _):
              let input = trimmed
              let sel = parseEmployeeSelection(input)
              if let idx = sel.index {
                  let candidates = (try? await Employee.query(on: db)
                      .filter(\.$isActive == false)
                      .filter(\.$fullName == sel.name)
                      .sort(\.$id, .ascending)
                      .all()) ?? []
                  if idx >= 1, idx <= candidates.count,
                     let eid = try? candidates[idx - 1].requireID() {
                      let emp = candidates[idx - 1]
                      var sess = await sessions.get(chatId) ?? Session()
                      sess.selectedEmployeeId = eid
                      sess.state = .adminArchiveConfirm
                      await sessions.set(chatId, sess)
                      await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Вернуть сотрудника \(emp.fullName)?", replyMarkup: KeyboardBuilder.yesNo())
                      return
                  } else {
                      await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник не найден.")
                      return
                  }
              }
              // Fallback: ищем по полному ФИО
              if let emp = try? await Employee.query(on: db).filter(\.$fullName == sel.name).filter(\.$isActive == false).first(),
                 let eid = try? emp.requireID() {
                  var sess = await sessions.get(chatId) ?? Session()
                  sess.selectedEmployeeId = eid
                  sess.state = .adminArchiveConfirm
                  await sessions.set(chatId, sess)
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Вернуть сотрудника \(emp.fullName)?", replyMarkup: KeyboardBuilder.yesNo())
              } else {
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник не найден.")
              }
              return
             
        case (.adminArchiveConfirm, "Нет"):
             await sessions.set(chatId, Session(state: .adminMenu))
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отменено.", replyMarkup: KeyboardBuilder.adminMenu())
             return

        case (.adminArchiveConfirm, "Да"):
             let eid = (await sessions.get(chatId))?.selectedEmployeeId
             if let eid = eid, let emp = try? await Employee.find(eid, on: db) {
                 emp.isActive = true
                 try? await emp.save(on: db)
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник снова активен.", replyMarkup: KeyboardBuilder.adminMenu())
             } else {
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сотрудник не найден.", replyMarkup: KeyboardBuilder.adminMenu())
             }
             await sessions.set(chatId, Session(state: .adminMenu))
             return

        case (.thanksMenu, "← Назад"):
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Главное меню:",
                replyMarkup: KeyboardBuilder.mainMenu()
            )
            await sessions.set(chatId, Session(state: .mainMenu))
            return
            
        case (.awaitingRecipient, "← Назад"):
            await sessions.set(chatId, Session(state: .thanksMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
            )
            return

        case (.awaitingReason, "← Назад"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page)
            return

        case (.awaitingReason, "Отмена"):
            await sessions.set(chatId, Session(state: .mainMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Действие отменено.",
                replyMarkup: KeyboardBuilder.mainMenu()
            )
            return

        // MARK: Шаги сценария: получатель → причина

        // Принят @username получателя
        case (.awaitingRecipient, _) where trimmed.hasPrefix("@"):
            await sessions.set(chatId, Session(state: .awaitingReason, to: trimmed))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Напиши короткое сообщение, за что хочешь сказать «спасибо». 🌟 (от \(minReasonLength) символов)",
                replyMarkup: KeyboardBuilder.reasonMenu()
            )
            return

        // Неверный ввод получателя → мягкая подсказка
        case (.awaitingRecipient, _):
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Нужно прислать @username получателя (пример: @nickname)."
            )
            await sessions.set(chatId, Session(state: .awaitingRecipient))
            return

        // Короткий текст причины → просим дописать
        case (.awaitingReason, _) where trimmed.count < minReasonLength:
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Сообщение должно содержать не менее \(minReasonLength) символов.",
                replyMarkup: KeyboardBuilder.reasonMenu()
            )
            await sessions.set(chatId, Session(state: .awaitingReason, to: currentTo))
            return

        // Принята причина → сохраняем
        case (.awaitingReason, _) where trimmed.count >= minReasonLength:
            // Нормализуем отправителя
            let fromUN = normalizeUsername(username ?? "unknown")

            // Получатель: либо выбран из каталога (FK), либо введён вручную через @username
            let recipientId = (await sessions.get(chatId))?.chosenEmployeeId
            let toUN = currentTo != nil ? normalizeUsername(currentTo!) : "@unknown"

            // Попробуем найти сотрудника-отправителя по его Telegram ID и привязать как FK
            var senderEmployeeID: UUID? = nil
            if let tg = userId {
                senderEmployeeID = try? await Employee.query(on: db)
                    .filter(\.$telegramId == tg)
                    .first()?
                    .requireID()
            }

            // 🚫 серверная защита "самому себе"
            if let sid = senderEmployeeID, let rid = recipientId, sid == rid {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Нельзя отправить спасибо самому себе 🙂 Выберите коллегу.",
                    replyMarkup: KeyboardBuilder.backToEmployeesList()
                )
                // возвращаем к выбору сотрудника и показываем актуальную страницу
                let page = (await sessions.get(chatId))?.page ?? 0
                await sessions.set(chatId, Session(state: .choosingEmployee, to: nil, page: page, chosenEmployeeId: nil))
                app.logger.info("self_kudos_blocked server tg:\(userId.map(String.init) ?? "nil")")
                return
            }

            // Создаём Kudos с привязкой получателя по FK (если выбран из каталога)
            let kudos = Kudos(
                ts: Date(),
                fromUserId: userId ?? 0,
                fromUsername: fromUN,
                fromName: username ?? fromUN,
                toUsername: toUN,              // фолбэк для экспорта/старых сценариев
                reason: trimmed,
                employeeId: recipientId,       // <-- ключевой фикс: FK получателя
                fromEmployeeId: senderEmployeeID
            )
            try? await kudos.save(on: db)
            
            // [ФИЧА - Уведомление получателю]
            // Проверяем, что у получателя есть ID в базе
            if let rid = recipientId,
               let recipientEmp = try? await Employee.find(rid, on: db),
               let recipientTgId = recipientEmp.telegramId {
                
                // --- НАЧАЛО ИЗМЕНЕНИЙ: Ищем имя отправителя ---
                // 1. По умолчанию берем никнейм (на всякий случай)
                var senderDisplayName = username ?? fromUN
                
                // 2. Пробуем найти отправителя в базе по его Telegram ID
                if let uid = userId,
                   let senderEmp = try? await Employee.query(on: db)
                       .filter(\.$telegramId == uid)
                       .first() {
                    // Если нашли — подставляем ФИО из базы
                    senderDisplayName = senderEmp.fullName
                }
                // --- КОНЕЦ ИЗМЕНЕНИЙ ---

                let notifyText = """
                🥳 <b>Тебе прилетело спасибо!</b>
                
                От: \(senderDisplayName)
                Текст: «\(trimmed)»
                """
                
                Task {
                    await TelegramService.sendMessage(
                        app,
                        api: api,
                        chatId: recipientTgId,
                        text: notifyText
                    )
                }
            }

            // Текст ответа — ФИО, если выбирали из каталога, иначе ник
            var targetText = toUN
            if let rid = recipientId, let emp = try? await Employee.find(rid, on: db) {
                targetText = emp.fullName
            }

            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "\(targetText) получил(а) твою благодарность 💛",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
            )
            await sessions.set(chatId, Session(state: .thanksMenu, to: nil, page: (await sessions.get(chatId))?.page, chosenEmployeeId: nil))
            return

        // MARK: Фолбэк
        default:
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Не понял команду. Нажми кнопку ниже.",
                replyMarkup: KeyboardBuilder.mainMenu()
            )
            await sessions.set(chatId, Session(state: .mainMenu))
            return
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
