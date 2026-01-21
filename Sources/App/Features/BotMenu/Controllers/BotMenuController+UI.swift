//
//  BotMenuController+UI.swift
//  ChatBot
//

import Vapor
import Fluent

extension BotMenuController {
    
    // MARK: - Helpers
    
    /// Нормализует ник: trim + lowercased + ensure leading '@'
    static func normalizeUsername(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return "@unknown" }
        return t.hasPrefix("@") ? t : "@\(t)"
    }
    
    /// Возвращает срез массива для страницы `page` (0-based) по `per` элементов
    static func pageSlice<T>(_ items: [T], page: Int, per: Int = 10) -> ArraySlice<T> {
        let start = max(0, page * per)
        let end = min(items.count, start + per)
        return items[start..<end]
    }
    
    /// Парсит выбор сотрудника из текста кнопки.
    /// Поддерживает формат "ФИО (N)" только для случаев, когда есть дубли ФИО.
    /// Возвращает базовое ФИО и порядковый номер (1-based), если он указан.
    static func parseEmployeeSelection(_ text: String) -> (name: String, index: Int?) {
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
    static func checkTelegramIdConflict(
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
    static func showEmployeesPage(
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
    static func showAdminEmployeesPage(
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
      static func showAdminLinkEmployeesPage(
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
          session.state = .adminLinkChoose
          session.page = p
          await sessions.set(chatId, session)
      }

     /// Показывает страницу сотрудников без telegramId для привязки Telegram
     static func showAdminTelegramBindEmployeesPage(
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
     static func showAdminTelegramChangeEmployeesPage(
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
}
