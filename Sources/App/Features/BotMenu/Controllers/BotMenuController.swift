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

      /// Проверяет конфликт Telegram ID перед сохранением
      private static func checkTelegramIdConflict(
          db: Database,
          newTelegramId: Int64,
          currentEmployeeId: UUID?
      ) async -> Employee? {
          guard let currentEmployeeId = currentEmployeeId else {
              return try? await Employee.query(on: db)
                  .filter(\.$telegramId == newTelegramId)
                  .first()
          }
          
          return try? await Employee.query(on: db)
              .filter(\.$telegramId == newTelegramId)
              .filter(\.$id != currentEmployeeId)
              .first()
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
             .filter(\.$telegramId != nil)
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
         let q = Employee.query(on: db)
             .filter(\.$isActive == active)

         // Deactivate should only show real, linked employees
         if active && targetState == .adminDeactivateChoose {
             q.filter(\.$telegramId != nil)
         }

         let all = (try? await q
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

       /// Показывает страницу сотрудников без telegramId для админа (для повторной привязки)
       private static func showAdminLinkEmployeesPage(
           app: Application,
           api: String,
           chatId: Int64,
           sessions: SessionStore,
           db: Database,
           page: Int
       ) async {
           let all = (try? await Employee.query(on: db)
               .filter(\.$telegramId == nil)
               .sort(\.$fullName, .ascending)
               .all()) ?? []
          
          let per = 10
          let totalPages = max(1, Int(ceil(Double(all.count) / Double(per))))
          let p = max(0, min(page, totalPages - 1))
          let slice = pageSlice(all, page: p, per: per)

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
              text: "Выбери сотрудника для привязки Telegram:",
              replyMarkup: KeyboardBuilder.employeesPage(
                  names: titles,
                  hasPrev: p > 0,
                  hasNext: p < totalPages - 1
              )
          )
          
           var session = await sessions.get(chatId) ?? Session()
           session.state = .adminLinkChoose
           session.page = p
           await sessions.set(chatId, session)
       }

      /// Показывает страницу сотрудников без telegramId для привязки Telegram
      private static func showAdminTelegramBindEmployeesPage(
          app: Application,
          api: String,
          chatId: Int64,
          sessions: SessionStore,
          db: Database,
          page: Int
      ) async {
          let all = (try? await Employee.query(on: db)
              .filter(\.$telegramId == nil)
              .sort(\.$fullName, .ascending)
              .all()) ?? []
           
          let per = 10
          let totalPages = max(1, Int(ceil(Double(all.count) / Double(per))))
          let p = max(0, min(page, totalPages - 1))
          let slice = pageSlice(all, page: p, per: per)
          
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
              text: "Выберите сотрудника для привязки Telegram:",
              replyMarkup: KeyboardBuilder.employeesPage(
                  names: titles,
                  hasPrev: p > 0,
                  hasNext: p < totalPages - 1
              )
          )
          
          var session = await sessions.get(chatId) ?? Session()
          session.state = .adminTelegramBindChoose
          session.page = p
          await sessions.set(chatId, session)
      }

      /// Показывает страницу сотрудников с telegramId для изменения Telegram
      private static func showAdminTelegramChangeEmployeesPage(
          app: Application,
          api: String,
          chatId: Int64,
          sessions: SessionStore,
          db: Database,
          page: Int
      ) async {
          let all = (try? await Employee.query(on: db)
              .filter(\.$telegramId != nil)
              .filter(\.$isActive == true)
              .sort(\.$fullName, .ascending)
              .all()) ?? []
           
          let per = 10
          let totalPages = max(1, Int(ceil(Double(all.count) / Double(per))))
          let p = max(0, min(page, totalPages - 1))
          let slice = pageSlice(all, page: p, per: per)
          
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
              text: "Выберите сотрудника для изменения Telegram ID:",
              replyMarkup: KeyboardBuilder.employeesPage(
                  names: titles,
                  hasPrev: p > 0,
                  hasNext: p < totalPages - 1
              )
          )
          
          var session = await sessions.get(chatId) ?? Session()
          session.state = .adminTelegramChangeChoose
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
                      .filter(\.$telegramId != nil)
                      .filter(\.$fullName == sel.name)
                      .all()) ?? []
                  
                  // Sort in-memory by uuidString to match keyboard sorting
                  let sortedCandidates = candidates.sorted { a, b in
                      let aId = (try? a.requireID())?.uuidString ?? ""
                      let bId = (try? b.requireID())?.uuidString ?? ""
                      return aId < bId
                  }
                  
                  if idx >= 1, idx <= sortedCandidates.count,
                     let empId = try? sortedCandidates[idx - 1].requireID() {
                      let emp = sortedCandidates[idx - 1]
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
                 .filter(\.$telegramId != nil)
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

         // MARK: - Admin Flow: Enhanced Telegram Binding

         case (.adminTelegramMenu, "➕ Привязать Telegram") where isAdmin(userId: userId, username: username):
             await showAdminTelegramBindEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0)
             return

         case (.adminTelegramMenu, "🔄 Изменить Telegram") where isAdmin(userId: userId, username: username):
             await showAdminTelegramChangeEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0)
             return

         case (.adminTelegramMenu, "← Назад"):
             var session = await sessions.get(chatId) ?? Session()
             session.state = .adminMenu
             await sessions.set(chatId, session)
             await TelegramService.sendMessage(
                 app, api: api, chatId: chatId,
                 text: "Раздел администратора:",
                 replyMarkup: KeyboardBuilder.adminMenu()
             )
             return

         // Navigation for adminTelegramBindChoose
         case (.adminTelegramBindChoose, "<"), (.adminTelegramBindChoose, "⬅"), (.adminTelegramBindChoose, "←"), (.adminTelegramBindChoose, "⭠"):
             let page = (await sessions.get(chatId))?.page ?? 0
             await showAdminTelegramBindEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))
             return

         case (.adminTelegramBindChoose, ">"), (.adminTelegramBindChoose, "➡"), (.adminTelegramBindChoose, "→"), (.adminTelegramBindChoose, "⭢"):
             let page = (await sessions.get(chatId))?.page ?? 0
             await showAdminTelegramBindEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1)
             return

         case (.adminTelegramBindChoose, "← Назад"):
             var session = await sessions.get(chatId) ?? Session()
             session.state = .adminTelegramMenu
             await sessions.set(chatId, session)
             await TelegramService.sendMessage(
                 app, api: api, chatId: chatId,
                 text: "Выберите действие:",
                 replyMarkup: KeyboardBuilder.adminTelegramMenu()
             )
             return

         // Employee selection for binding
         case (.adminTelegramBindChoose, _):
             let input = trimmed
             let sel = parseEmployeeSelection(input)
             
             do {
                 let candidates = (try? await Employee.query(on: db)
                     .filter(\.$telegramId == nil)
                     .filter(\.$fullName == sel.name)
                     .all()) ?? []
                 
                 let sortedCandidates = candidates.sorted { a, b in
                     let aId = (try? a.requireID())?.uuidString ?? ""
                     let bId = (try? b.requireID())?.uuidString ?? ""
                     return aId < bId
                 }
                 
                 let emp: Employee?
                 if let idx = sel.index {
                     emp = (idx >= 1 && idx <= sortedCandidates.count) ? sortedCandidates[idx - 1] : nil
                 } else {
                     emp = sortedCandidates.first
                 }
                 
                 guard let emp = emp, let empId = try? emp.requireID() else {
                     await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник не найден или уже привязан.")
                     return
                 }

                 var session = await sessions.get(chatId) ?? Session()
                 session.selectedEmployeeId = empId
                 session.state = .adminTelegramBindAwaitForward
                 await sessions.set(chatId, session)

                 await TelegramService.sendMessage(
                     app, api: api, chatId: chatId,
                     text: "Выбран сотрудник: \(emp.fullName)\nTelegram не привязан.\n\nПерешлите сюда любое сообщение от сотрудника (forward).\nЕсли Telegram скрыт в пересылках, нажмите «🔗 Получить код» и отправьте его сотруднику.",
                     replyMarkup: KeyboardBuilder.adminTelegramForwardMenu()
                 )

                  app.logger.info("admin_tg_bind_choose employeeId=\(empId)")
                  return
              }

         case (.adminTelegramBindAwaitForward, "Отмена"):
             // Cancel binding: remove pending links and (if safe) delete the unlinked employee created for binding
             let empId = (await sessions.get(chatId))?.selectedEmployeeId

             if let empId {
                 do {
                     // Always remove unused pending links for this employee
                     try await PendingLink.query(on: db)
                         .filter(\.$employee.$id == empId)
                         .filter(\.$isUsed == false)
                         .delete()

                     if let emp = try await Employee.find(empId, on: db) {
                         // Only delete employees that are still unlinked and inactive
                         if emp.telegramId == nil && emp.isActive == false {
                             // Safety: do not delete if there are any kudos referencing this employee
                             let kudosCount = try await Kudos.query(on: db)
                                 .group(.or) { or in
                                     or.filter(\.$employee.$id == empId)          // toEmployeeId
                                     or.filter(\.$fromEmployee.$id == empId)     // fromEmployeeId
                                 }
                                 .count()

                             if kudosCount == 0 {
                                 try await emp.delete(on: db)
                                 app.logger.info("admin_tg_bind_cancel_deleted_employee employeeId=\(empId)")
                             } else {
                                 app.logger.info("admin_tg_bind_cancel_skipped_with_kudos employeeId=\(empId) kudos=\(kudosCount)")
                             }
                         }
                     }
                 } catch {
                     app.logger.error("admin_tg_bind_cancel_cleanup_failed employeeId=\(empId) error=\(error)")
                 }
             }

             var s = await sessions.get(chatId) ?? Session()
             s.selectedEmployeeId = nil
             s.state = .adminTelegramMenu
             await sessions.set(chatId, s)

             await TelegramService.sendMessage(
                 app, api: api, chatId: chatId,
                 text: "Отменено.",
                 replyMarkup: KeyboardBuilder.adminTelegramMenu()
             )
             return
         // Handle forward message for binding
         case (.adminTelegramBindAwaitForward, "← Назад"):
             var session = await sessions.get(chatId) ?? Session()
             session.state = .adminTelegramBindChoose
             let page = session.page ?? 0
             await sessions.set(chatId, session)
             await showAdminTelegramBindEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page)
             return
         case (.adminTelegramBindAwaitForward, _):
             guard let session = await sessions.get(chatId), let empId = session.selectedEmployeeId else {
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сессия потеряна. Начните заново.")
                 var newSession = await sessions.get(chatId) ?? Session()
                 newSession.state = .adminTelegramMenu
                 await sessions.set(chatId, newSession)
                 return
             }

              guard let emp = try? await Employee.find(empId, on: db) else {
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сотрудник не найден.")
                  var newSession = await sessions.get(chatId) ?? Session()
                  newSession.state = .adminTelegramMenu
                  await sessions.set(chatId, newSession)
                  return
              }

              // Handle "Get code" button
              if t == "🔗 Получить код" {
                 do {
                     // 1. Удаляем старые неиспользованные заявки для этого сотрудника
                     try await PendingLink.query(on: db)
                         .filter(\.$employee.$id == empId)
                         .filter(\.$isUsed == false)
                         .delete()

                     // 2. Генерируем новый уникальный код (до 5 попыток)
                     var code = ""
                     var success = false
                     for _ in 1...5 {
                         let randomCode = String(Int.random(in: 100000...999999))
                         let existing = try await PendingLink.query(on: db).filter(\.$code == randomCode).first()
                         if existing == nil {
                             code = randomCode
                             success = true
                             break
                         }
                     }

                     guard success else {
                         await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Не удалось сгенерировать уникальный код. Попробуй еще раз.")
                         return
                     }

                     // 3. Создаем новый PendingLink
                     let expiresAt = Date().addingTimeInterval(15 * 60)
                     let pending = PendingLink(code: code, employeeId: empId, createdByAdminTgId: userId, expiresAt: expiresAt)
                     try await pending.save(on: db)

                     let msg = """
                     Код для привязки Telegram к сотруднику <b>\(emp.fullName)</b> сгенерирован! ✅

                     Код привязки: <code>\(code)</code>

                     Инструкция для сотрудника:
                     1. Зайти в этот бот
                     2. Написать команду: <code>/link \(code)</code>

                     Код действует 15 минут.
                     """
                     await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg, replyMarkup: KeyboardBuilder.adminTelegramForwardMenu())

                     app.logger.info("admin_tg_token_generated employeeId=\(empId) adminId=\(userId ?? 0) code=\(code)")
                     return
                 } catch {
                     app.logger.error("Failed to generate token for binding: \(error)")
                     await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: \(error.localizedDescription)")
                     return
                 }
             }

             // Handle forward message
             guard let fwd = message.forward_from else {
                 await TelegramService.sendMessage(
                     app, api: api, chatId: chatId,
                     text: "Не удалось получить Telegram ID из пересылки.\nУ пользователя включена приватность пересылок.\nИспользуйте кнопку «🔗 Получить код».",
                     replyMarkup: KeyboardBuilder.adminTelegramForwardMenu()
                 )
                 app.logger.info("admin_tg_forward_missing employeeId=\(empId)")
                 return
             }

             let newTelegramId = fwd.id

             // Check for conflicts
             if let conflictingEmployee = await checkTelegramIdConflict(db: db, newTelegramId: newTelegramId, currentEmployeeId: empId) {
                 if let conflictingEmpId = try? conflictingEmployee.requireID(), conflictingEmpId != empId {
                     await TelegramService.sendMessage(
                         app, api: api, chatId: chatId,
                         text: "Этот Telegram уже привязан к сотруднику \(conflictingEmployee.fullName).\nПроверьте аккаунт или сначала измените привязку у другого сотрудника.",
                         replyMarkup: KeyboardBuilder.adminTelegramForwardMenu()
                     )
                     app.logger.info("admin_tg_conflict newTg=\(newTelegramId) existingEmployeeId=\(conflictingEmpId) targetEmployeeId=\(empId)")
                     return
                 }
             }

             // Update employee
             do {
                 emp.telegramId = newTelegramId
                 emp.isActive = true
                 try await emp.save(on: db)

                 // Delete any pending links for this employee
                 try await PendingLink.query(on: db)
                     .filter(\.$employee.$id == empId)
                     .delete()

                 await TelegramService.sendMessage(
                     app, api: api, chatId: chatId,
                     text: "✅ Telegram успешно привязан для \(emp.fullName)",
                     replyMarkup: KeyboardBuilder.adminTelegramMenu()
                 )

                 app.logger.info("admin_tg_bind_forward_success employeeId=\(empId) newTg=\(newTelegramId)")

                 var session = await sessions.get(chatId) ?? Session()
                 session.state = .adminTelegramMenu
                 session.selectedEmployeeId = nil
                 await sessions.set(chatId, session)
                 return
             } catch {
                 app.logger.error("Failed to bind Telegram ID: \(error)")
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка при сохранении: \(error.localizedDescription)")
                 return
             }


         // Navigation for adminTelegramChangeChoose
         case (.adminTelegramChangeChoose, "<"), (.adminTelegramChangeChoose, "⬅"), (.adminTelegramChangeChoose, "←"), (.adminTelegramChangeChoose, "⭠"):
             let page = (await sessions.get(chatId))?.page ?? 0
             await showAdminTelegramChangeEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))
             return

         case (.adminTelegramChangeChoose, ">"), (.adminTelegramChangeChoose, "➡"), (.adminTelegramChangeChoose, "→"), (.adminTelegramChangeChoose, "⭢"):
             let page = (await sessions.get(chatId))?.page ?? 0
             await showAdminTelegramChangeEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1)
             return

         case (.adminTelegramChangeChoose, "← Назад"):
             var session = await sessions.get(chatId) ?? Session()
             session.state = .adminTelegramMenu
             await sessions.set(chatId, session)
             await TelegramService.sendMessage(
                 app, api: api, chatId: chatId,
                 text: "Выберите действие:",
                 replyMarkup: KeyboardBuilder.adminTelegramMenu()
             )
             return

         // Employee selection for changing
         case (.adminTelegramChangeChoose, _):
             let input = trimmed
             let sel = parseEmployeeSelection(input)
             
             do {
                 let candidates = (try? await Employee.query(on: db)
                     .filter(\.$telegramId != nil)
                     .filter(\.$isActive == true)
                     .filter(\.$fullName == sel.name)
                     .all()) ?? []
                 
                 let sortedCandidates = candidates.sorted { a, b in
                     let aId = (try? a.requireID())?.uuidString ?? ""
                     let bId = (try? b.requireID())?.uuidString ?? ""
                     return aId < bId
                 }
                 
                 let emp: Employee?
                 if let idx = sel.index {
                     emp = (idx >= 1 && idx <= sortedCandidates.count) ? sortedCandidates[idx - 1] : nil
                 } else {
                     emp = sortedCandidates.first
                 }
                 
                 guard let emp = emp, let empId = try? emp.requireID(), let currentTgId = emp.telegramId else {
                     await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник не найден или у него нет Telegram ID.")
                     return
                 }

                 var session = await sessions.get(chatId) ?? Session()
                 session.selectedEmployeeId = empId
                 session.state = .adminTelegramChangeAwaitForward
                 await sessions.set(chatId, session)

                 await TelegramService.sendMessage(
                     app, api: api, chatId: chatId,
                     text: "Выбран сотрудник: \(emp.fullName)\nТекущий Telegram ID: \(currentTgId)\n\nПерешлите сообщение от нового Telegram-аккаунта сотрудника.\nЕсли Telegram скрыт, нажмите «🔗 Получить код».",
                     replyMarkup: KeyboardBuilder.adminTelegramForwardMenu()
                 )

                  app.logger.info("admin_tg_change_choose employeeId=\(empId) currentTg=\(currentTgId)")
                  return
              }

         case (.adminTelegramChangeAwaitForward, "Отмена"):
             var s = await sessions.get(chatId) ?? Session()
             s.selectedEmployeeId = nil
             s.state = .adminTelegramMenu
             await sessions.set(chatId, s)

             await TelegramService.sendMessage(
                 app, api: api, chatId: chatId,
                 text: "Отменено.",
                 replyMarkup: KeyboardBuilder.adminTelegramMenu()
             )
             return
         // Handle forward message for changing
         case (.adminTelegramChangeAwaitForward, "← Назад"):
             var session = await sessions.get(chatId) ?? Session()
             session.state = .adminTelegramChangeChoose
             let page = session.page ?? 0
             await sessions.set(chatId, session)
             await showAdminTelegramChangeEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page)
             return
         case (.adminTelegramChangeAwaitForward, _):
             guard let session = await sessions.get(chatId), let empId = session.selectedEmployeeId else {
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сессия потеряна. Начните заново.")
                 var newSession = await sessions.get(chatId) ?? Session()
                 newSession.state = .adminTelegramMenu
                 await sessions.set(chatId, newSession)
                 return
             }

              guard let emp = try? await Employee.find(empId, on: db), let currentTgId = emp.telegramId else {
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сотрудник не найден или у него нет Telegram ID.")
                  var newSession = await sessions.get(chatId) ?? Session()
                  newSession.state = .adminTelegramMenu
                  await sessions.set(chatId, newSession)
                  return
              }

              // Handle "Get code" button
              if t == "🔗 Получить код" {
                 do {
                     // 1. Удаляем старые неиспользованные заявки для этого сотрудника
                     try await PendingLink.query(on: db)
                         .filter(\.$employee.$id == empId)
                         .filter(\.$isUsed == false)
                         .delete()

                     // 2. Генерируем новый уникальный код (до 5 попыток)
                     var code = ""
                     var success = false
                     for _ in 1...5 {
                         let randomCode = String(Int.random(in: 100000...999999))
                         let existing = try await PendingLink.query(on: db).filter(\.$code == randomCode).first()
                         if existing == nil {
                             code = randomCode
                             success = true
                             break
                         }
                     }

                     guard success else {
                         await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Не удалось сгенерировать уникальный код. Попробуй еще раз.")
                         return
                     }

                     // 3. Создаем новый PendingLink
                     let expiresAt = Date().addingTimeInterval(15 * 60)
                     let pending = PendingLink(code: code, employeeId: empId, createdByAdminTgId: userId, expiresAt: expiresAt)
                     try await pending.save(on: db)

                     let msg = """
                     Код для изменения Telegram ID сотрудника <b>\(emp.fullName)</b> сгенерирован! ✅

                     Код привязки: <code>\(code)</code>

                     Инструкция для сотрудника:
                     1. Зайти в этот бот
                     2. Написать команду: <code>/link \(code)</code>

                     Код действует 15 минут.
                     """
                     await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg, replyMarkup: KeyboardBuilder.adminTelegramForwardMenu())

                     app.logger.info("admin_tg_token_generated employeeId=\(empId) adminId=\(userId ?? 0) code=\(code)")
                     return
                 } catch {
                     app.logger.error("Failed to generate token for changing: \(error)")
                     await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: \(error.localizedDescription)")
                     return
                 }
             }

             // Handle forward message
             guard let fwd = message.forward_from else {
                 await TelegramService.sendMessage(
                     app, api: api, chatId: chatId,
                     text: "Не удалось получить Telegram ID из пересылки.\nУ пользователя включена приватность пересылок.\nИспользуйте кнопку «🔗 Получить код».",
                     replyMarkup: KeyboardBuilder.adminTelegramForwardMenu()
                 )
                 app.logger.info("admin_tg_forward_missing employeeId=\(empId)")
                 return
             }

             let newTelegramId = fwd.id

             // Check if same as current
             if newTelegramId == currentTgId {
                 await TelegramService.sendMessage(
                     app, api: api, chatId: chatId,
                     text: "Этот Telegram уже привязан к сотруднику.",
                     replyMarkup: KeyboardBuilder.adminTelegramForwardMenu()
                 )
                 return
             }

             // Check for conflicts
             if let conflictingEmployee = await checkTelegramIdConflict(db: db, newTelegramId: newTelegramId, currentEmployeeId: empId) {
                 if let conflictingEmpId = try? conflictingEmployee.requireID(), conflictingEmpId != empId {
                     await TelegramService.sendMessage(
                         app, api: api, chatId: chatId,
                         text: "Этот Telegram уже привязан к сотруднику \(conflictingEmployee.fullName).\nПроверьте аккаунт или сначала измените привязку у другого сотрудника.",
                         replyMarkup: KeyboardBuilder.adminTelegramForwardMenu()
                     )
                     app.logger.info("admin_tg_conflict newTg=\(newTelegramId) existingEmployeeId=\(conflictingEmpId) targetEmployeeId=\(empId)")
                     return
                 }
             }

             // Update employee
             do {
                 let oldTgId = emp.telegramId
                 emp.telegramId = newTelegramId
                 try await emp.save(on: db)

                 // Delete any pending links for this employee
                 try await PendingLink.query(on: db)
                     .filter(\.$employee.$id == empId)
                     .delete()

                 await TelegramService.sendMessage(
                     app, api: api, chatId: chatId,
                     text: "✅ Telegram ID обновлен для \(emp.fullName)",
                     replyMarkup: KeyboardBuilder.adminTelegramMenu()
                 )

                 app.logger.info("admin_tg_change_forward_success employeeId=\(empId) oldTg=\(oldTgId ?? 0) newTg=\(newTelegramId)")

                 var session = await sessions.get(chatId) ?? Session()
                 session.state = .adminTelegramMenu
                 session.selectedEmployeeId = nil
                 await sessions.set(chatId, session)
                 return
             } catch {
                 app.logger.error("Failed to change Telegram ID: \(error)")
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка при сохранении: \(error.localizedDescription)")
                 return
             }


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

        case (_, let cmd) where cmd.contains("Привязка Telegram") && isAdmin(userId: userId, username: username):
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Выберите действие:",
                replyMarkup: KeyboardBuilder.adminTelegramMenu()
            )
            var session = await sessions.get(chatId) ?? Session()
            session.state = .adminTelegramMenu
            await sessions.set(chatId, session)
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
                  text: """
                  Перешли любое сообщение от сотрудника, чтобы я мог узнать его Telegram ID.
                  
                  <i>Если у сотрудника скрыт профиль, нажми кнопку ниже для привязки через код.</i>
                  """,
                  replyMarkup: KeyboardBuilder.adminAddForwardMenu()
              )
              return

        
        case (.adminAddAskForward, "← Назад"):
             // Back to start of add flow
             await sessions.set(chatId, Session(state: .adminAddAskName))
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Введи Фамилию и Имя", replyMarkup: KeyboardBuilder.back())
             return

        case (.adminAddAskForward, "🔗 Привязать через код"):
             guard let session = await sessions.get(chatId), let draftName = session.draftFullName else {
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сессия потеряна. Начни заново.", replyMarkup: KeyboardBuilder.adminMenu())
                 await sessions.set(chatId, Session(state: .adminMenu))
                 return
             }

             // Создаем сотрудника или переиспользуем уже созданного (если админ нажал кнопку повторно)
             let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
             guard !name.isEmpty else {
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: имя пустое. Начни заново.", replyMarkup: KeyboardBuilder.adminMenu())
                 await sessions.set(chatId, Session(state: .adminMenu))
                 return
             }

             do {
                 // Пытаемся найти уже созданного сотрудника, ожидающего привязки Telegram
                 let existing = try await Employee.query(on: db)
                     .filter(\.$fullName == name)
                     .filter(\.$telegramId == nil)
                     .filter(\.$isActive == false)
                     .sort(\.$id, .ascending)
                     .first()

                 let emp: Employee
                 if let existing {
                     emp = existing
                 } else {
                     let newEmp = Employee(fullName: name, isActive: false)
                     try await newEmp.save(on: db)
                     emp = newEmp
                 }

                 let empId = try emp.requireID()

                 // Генерируем уникальный код (до 5 попыток)
                 var code = ""
                 var success = false
                 for _ in 1...5 {
                     let randomCode = String(Int.random(in: 100000...999999))
                     let existing = try await PendingLink.query(on: db).filter(\.$code == randomCode).first()
                     if existing == nil {
                         code = randomCode
                         success = true
                         break
                     }
                 }

                 guard success else {
                     await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Не удалось сгенерировать уникальный код. Попробуй нажать кнопку еще раз.", replyMarkup: KeyboardBuilder.adminAddForwardMenu())
                     return
                 }

                 let expiresAt = Date().addingTimeInterval(15 * 60)
                 let pending = PendingLink(code: code, employeeId: empId, createdByAdminTgId: userId, expiresAt: expiresAt)
                 try await pending.save(on: db)

                 let msg = """
                 Сотрудник <b>\(name)</b> создан! ✅

                 Код привязки: <code>\(code)</code>

                 Инструкция для сотрудника:
                 1. Зайти в этот бот
                 2. Написать команду: <code>/link \(code)</code>

                 Код действует 15 минут.
                 """
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg, replyMarkup: KeyboardBuilder.adminMenu())
                 var s = await sessions.get(chatId) ?? Session()
                 s.state = .adminMenu
                 s.draftFullName = nil
                 s.draftTelegramId = nil
                 s.selectedEmployeeId = nil
                 s.chosenEmployeeId = nil
                 await sessions.set(chatId, s)

                 app.logger.info("pending_created: adminId=\(userId ?? 0), employeeId=\(empId), code=\(code)")
             } catch {
                 app.logger.error("Failed to create pending link: \(error)")
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: \(error.localizedDescription)", replyMarkup: KeyboardBuilder.adminMenu())
                 var s = await sessions.get(chatId) ?? Session()
                 s.state = .adminMenu
                 s.draftFullName = nil
                 s.draftTelegramId = nil
                 s.selectedEmployeeId = nil
                 s.chosenEmployeeId = nil
                 await sessions.set(chatId, s)
             }
             return

        case (.adminAddAskForward, _):
             // Check forward
             guard let fwd = message.forward_from else {
                 await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Это не пересланное сообщение или профиль скрыт. Попробуй переслать другое сообщение (не от бота, а от человека).", replyMarkup: KeyboardBuilder.adminAddForwardMenu())
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
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Перешли другое сообщение.", replyMarkup: KeyboardBuilder.adminAddForwardMenu())
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
                    var s = await sessions.get(chatId) ?? Session()
                    s.draftFullName = nil
                    s.draftTelegramId = nil
                    s.selectedEmployeeId = nil
                    s.chosenEmployeeId = nil
                    s.state = .adminMenu
                    await sessions.set(chatId, s)
                    return
                }
                  
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    await TelegramService.sendMessage(
                        app, api: api, chatId: chatId,
                        text: "Ошибка: имя пустое. Введи Фамилию и Имя.",
                        replyMarkup: KeyboardBuilder.adminMenu()
                    )
                    var s = await sessions.get(chatId) ?? Session()
                    s.draftFullName = nil
                    s.draftTelegramId = nil
                    s.selectedEmployeeId = nil
                    s.chosenEmployeeId = nil
                    s.state = .adminMenu
                    await sessions.set(chatId, s)
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
                var s = await sessions.get(chatId) ?? Session()
                s.draftFullName = nil
                s.draftTelegramId = nil
                s.selectedEmployeeId = nil
                s.chosenEmployeeId = nil
                s.state = .adminMenu
                await sessions.set(chatId, s)
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
                       .all()) ?? []
                   
                   // Sort in-memory by uuidString to match keyboard sorting
                   let sortedCandidates = candidates.sorted { a, b in
                       let aId = (try? a.requireID())?.uuidString ?? ""
                       let bId = (try? b.requireID())?.uuidString ?? ""
                       return aId < bId
                   }
                   
                   if idx >= 1, idx <= sortedCandidates.count,
                      let eid = try? sortedCandidates[idx - 1].requireID() {
                       let emp = sortedCandidates[idx - 1]
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
                        .all()) ?? []
                    
                    // Sort in-memory by uuidString to match keyboard sorting
                    let sortedCandidates = candidates.sorted { a, b in
                        let aId = (try? a.requireID())?.uuidString ?? ""
                        let bId = (try? b.requireID())?.uuidString ?? ""
                        return aId < bId
                    }
                    
                    if idx >= 1, idx <= sortedCandidates.count,
                       let eid = try? sortedCandidates[idx - 1].requireID() {
                        let emp = sortedCandidates[idx - 1]
                       var sess = await sessions.get(chatId) ?? Session()
                       sess.selectedEmployeeId = eid
                       sess.state = .adminArchiveActions
                       await sessions.set(chatId, sess)
                       await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Выбран сотрудник: \(emp.fullName)\nЧто сделать?", replyMarkup: KeyboardBuilder.adminArchiveActionsMenu())
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
                   sess.state = .adminArchiveActions
                   await sessions.set(chatId, sess)
                   await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Выбран сотрудник: \(emp.fullName)\nЧто сделать?", replyMarkup: KeyboardBuilder.adminArchiveActionsMenu())
               } else {
                   await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник не найден.")
               }
               return
               
         case (.adminArchiveActions, "✅ Восстановить"):
              let eid = (await sessions.get(chatId))?.selectedEmployeeId
              if let eid = eid, let emp = try? await Employee.find(eid, on: db) {
                  var sess = await sessions.get(chatId) ?? Session()
                  sess.state = .adminArchiveConfirm
                  await sessions.set(chatId, sess)
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Вернуть сотрудника \(emp.fullName)?", replyMarkup: KeyboardBuilder.yesNo())
              } else {
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сотрудник не найден.", replyMarkup: KeyboardBuilder.adminMenu())
                  await sessions.set(chatId, Session(state: .adminMenu))
              }
              return

         case (.adminArchiveActions, "🗑 Удалить из системы"):
              let eid = (await sessions.get(chatId))?.selectedEmployeeId
              if let eid = eid, let emp = try? await Employee.find(eid, on: db) {
                  // Подсчитываем количество Kudos
                  let countTo = (try? await Kudos.query(on: db).filter(\.$employee.$id == eid).count()) ?? 0
                  let countFrom = (try? await Kudos.query(on: db).filter(\.$fromEmployee.$id == eid).count()) ?? 0
                  
                  var sess = await sessions.get(chatId) ?? Session()
                  sess.state = .adminArchiveDeleteConfirm
                  await sessions.set(chatId, sess)
                  
                  let msg = """
                  ⚠️ <b>ВНИМАНИЕ!</b> Это действие необратимо.
                  
                  Будет удален сотрудник <b>\(emp.fullName)</b> и все его благодарности:
                  - Полученных: \(countTo)
                  - Отправленных: \(countFrom)
                  
                  Удалить сотрудника из системы навсегда?
                  """
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg, replyMarkup: KeyboardBuilder.yesNo())
              } else {
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сотрудник не найден.", replyMarkup: KeyboardBuilder.adminMenu())
                  await sessions.set(chatId, Session(state: .adminMenu))
              }
              return

         case (.adminArchiveActions, "← Назад"):
              let page = (await sessions.get(chatId))?.page ?? 0
              await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page, active: false, targetState: .adminArchiveChoose)
              return

         case (.adminArchiveDeleteConfirm, "Нет"):
              let sess = await sessions.get(chatId) ?? Session()
              if let eid = sess.selectedEmployeeId, let emp = try? await Employee.find(eid, on: db) {
                  var newSess = sess
                  newSess.state = .adminArchiveActions
                  await sessions.set(chatId, newSess)
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Удаление отменено.\n\nВыбран сотрудник: \(emp.fullName)\nЧто сделать?", replyMarkup: KeyboardBuilder.adminArchiveActionsMenu())
              } else {
                  await sessions.set(chatId, Session(state: .adminMenu))
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Отменено.", replyMarkup: KeyboardBuilder.adminMenu())
              }
              return

         case (.adminArchiveDeleteConfirm, "Да"):
              guard let sess = await sessions.get(chatId), let eid = sess.selectedEmployeeId else {
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: сессия потеряна.", replyMarkup: KeyboardBuilder.adminMenu())
                  await sessions.set(chatId, Session(state: .adminMenu))
                  return
              }
              
              do {
                  try await db.transaction { tx in
                      // 1. Считаем для лога перед удалением
                      let countTo = try await Kudos.query(on: tx).filter(\.$employee.$id == eid).count()
                      let countFrom = try await Kudos.query(on: tx).filter(\.$fromEmployee.$id == eid).count()
                      
                      // 2. Удаляем Kudos
                      try await Kudos.query(on: tx).group(.or) { or in
                          or.filter(\.$employee.$id == eid)
                          or.filter(\.$fromEmployee.$id == eid)
                      }.delete()
                      
                      // 3. Удаляем сотрудника
                      guard let emp = try await Employee.find(eid, on: tx) else {
                          throw Abort(.notFound, reason: "Employee not found")
                      }
                      try await emp.delete(on: tx)
                      
                      // 4. Логируем
                      app.logger.info("admin_full_delete_employee id=\(eid) kudos_to=\(countTo) kudos_from=\(countFrom) admin_tg=\(userId.map(String.init) ?? username ?? "unknown")")
                  }
                  
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник и все его благодарности полностью удалены из системы. 🗑✅", replyMarkup: KeyboardBuilder.adminMenu())
              } catch {
                  app.logger.error("admin_full_delete_employee_failed id=\(eid) error=\(error)")
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка при удалении: \(error.localizedDescription)", replyMarkup: KeyboardBuilder.adminMenu())
              }
              await sessions.set(chatId, Session(state: .adminMenu))
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

        // MARK: - Admin Flow: Link Telegram (Regenerate Code)
        
        case (.adminLinkChoose, "<"), (.adminLinkChoose, "⬅"), (.adminLinkChoose, "←"), (.adminLinkChoose, "⭠"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminLinkEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))
            return

        case (.adminLinkChoose, ">"), (.adminLinkChoose, "➡"), (.adminLinkChoose, "→"), (.adminLinkChoose, "⭢"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showAdminLinkEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: page + 1)
            return
            
        case (.adminLinkChoose, "← Назад"):
             await sessions.set(chatId, Session(state: .adminMenu))
             await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Админка:", replyMarkup: KeyboardBuilder.adminMenu())
             return

          case (.adminLinkChoose, _):
               let input = trimmed
               let sel = parseEmployeeSelection(input)
               
                do {
                    let candidates = (try? await Employee.query(on: db)
                        .filter(\.$telegramId == nil)
                        .filter(\.$fullName == sel.name)
                        .all()) ?? []
                   
                   // Sort in-memory by uuidString to match keyboard sorting
                   let sortedCandidates = candidates.sorted { a, b in
                       let aId = (try? a.requireID())?.uuidString ?? ""
                       let bId = (try? b.requireID())?.uuidString ?? ""
                       return aId < bId
                   }
                   
                   let emp: Employee?
                   if let idx = sel.index {
                       emp = (idx >= 1 && idx <= sortedCandidates.count) ? sortedCandidates[idx - 1] : nil
                   } else {
                       emp = sortedCandidates.first
                   }
                  
                  guard let emp = emp, let empId = try? emp.requireID() else {
                      await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Сотрудник не найден или уже привязан.")
                      return
                  }
                  
                  // 1. Удаляем старые неиспользованные заявки для этого сотрудника
                  try await PendingLink.query(on: db)
                      .filter(\.$employee.$id == empId)
                      .filter(\.$isUsed == false)
                      .delete()
                  
                  // 2. Генерируем новый уникальный код (до 5 попыток)
                  var code = ""
                  var success = false
                  for _ in 1...5 {
                      let randomCode = String(Int.random(in: 100000...999999))
                      let existing = try await PendingLink.query(on: db).filter(\.$code == randomCode).first()
                      if existing == nil {
                          code = randomCode
                          success = true
                          break
                      }
                  }
                  
                  guard success else {
                      await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Не удалось сгенерировать уникальный код. Попробуй еще раз.")
                      return
                  }
                  
                  // 3. Создаем новый PendingLink
                  let expiresAt = Date().addingTimeInterval(15 * 60)
                  let pending = PendingLink(code: code, employeeId: empId, createdByAdminTgId: userId, expiresAt: expiresAt)
                  try await pending.save(on: db)
                  
                  let msg = """
                  Новый код для сотрудника <b>\(emp.fullName)</b> сгенерирован! ✅
                  
                  Код привязки: <code>\(code)</code>
                  
                  Инструкция для сотрудника:
                  1. Зайти в этот бот
                  2. Написать команду: <code>/start \(code)</code>
                  
                  Код действует 15 минут.
                  """
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg, replyMarkup: KeyboardBuilder.adminMenu())
                  await sessions.set(chatId, Session(state: .adminMenu))
                  
                  app.logger.info("pending_regenerated: adminId=\(userId ?? 0), employeeId=\(empId), code=\(code)")
              } catch {
                  app.logger.error("Failed to regenerate pending link: \(error)")
                  await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: \(error.localizedDescription)", replyMarkup: KeyboardBuilder.adminMenu())
                  await sessions.set(chatId, Session(state: .adminMenu))
              }
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

            var s = await sessions.get(chatId) ?? Session()
            s.state = .awaitingReason
            s.to = currentTo
            // важно: не трогаем chosenEmployeeId и page
            await sessions.set(chatId, s)
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
