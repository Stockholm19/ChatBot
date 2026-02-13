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
        page: Int,
        editMessageId: Int? = nil
    ) async {
        let data = await loadActiveEmployeesPage(db: db, page: page)
        let inlineOptions = data.slice.compactMap { emp -> KeyboardBuilder.EmployeeInlineOption? in
            guard let id = try? emp.requireID() else { return nil }
            return .init(id: id, title: data.titleById[id] ?? emp.fullName)
        }

        let text = "Кому сказать спасибо? (стр. \(data.page + 1)/\(data.totalPages))"
        let keyboard = KeyboardBuilder.employeesInlinePage(
            options: inlineOptions,
            hasPrev: data.page > 0,
            hasNext: data.page < data.totalPages - 1,
            page: data.page,
            callbackPrefix: "emp"
        )

        await sendOrEditInlineEmployeesList(
            app: app,
            api: api,
            chatId: chatId,
            text: text,
            inlineMarkup: keyboard,
            editMessageId: editMessageId
        )

        await sessions.set(chatId, Session(state: .choosingEmployee, page: data.page))
    }

    static func loadActiveEmployeesPage(db: Database, page: Int) async -> (all: [Employee], slice: ArraySlice<Employee>, titleById: [UUID: String], page: Int, totalPages: Int) {
        let all = (try? await Employee.query(on: db)
            .filter(\.$isActive == true)
            .filter(\.$telegramId != nil)
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

        return (all: all, slice: slice, titleById: titleById, page: p, totalPages: totalPages)
    }

    static func sendOrEditInlineEmployeesList(
        app: Application,
        api: String,
        chatId: Int64,
        text: String,
        inlineMarkup: TgInlineKeyboardMarkup,
        editMessageId: Int?
    ) async {
        if let editMessageId {
            await TelegramService.editMessageText(
                app,
                api: api,
                chatId: chatId,
                messageId: editMessageId,
                text: text,
                inlineMarkup: inlineMarkup
            )
            return
        }

        await TelegramService.hideReplyKeyboardSilently(
            app,
            api: api,
            chatId: chatId
        )

        await TelegramService.sendMessage(
            app,
            api: api,
            chatId: chatId,
            text: text,
            inlineMarkup: inlineMarkup
        )
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
        targetState: SessionState,
        editMessageId: Int? = nil
    ) async {
        let q = Employee.query(on: db)
            .filter(\.$isActive == active)

        if active && targetState == .adminDeactivateChoose {
            q.filter(\.$telegramId != nil)
        }

        let all = (try? await q
            .sort(\.$fullName, .ascending)
            .all()) ?? []

        let data = employeePageData(all: all, page: page)
        let title = active
            ? "Кого деактивировать? (стр. \(data.page + 1)/\(data.totalPages))"
            : "Кого вернуть из архива? (стр. \(data.page + 1)/\(data.totalPages))"
        let callbackPrefix = targetState == .adminDeactivateChoose ? "adm:deact" : "adm:arch"

        await sendAdminInlineList(
            app: app,
            api: api,
            chatId: chatId,
            text: title,
            data: data,
            callbackPrefix: callbackPrefix,
            editMessageId: editMessageId
        )

        var session = await sessions.get(chatId) ?? Session()
        session.state = targetState
        session.page = data.page
        await sessions.set(chatId, session)
    }

    static func showAdminLinkEmployeesPage(
        app: Application,
        api: String,
        chatId: Int64,
        sessions: SessionStore,
        db: Database,
        page: Int,
        editMessageId: Int? = nil
    ) async {
        let all = (try? await Employee.query(on: db)
            .filter(\.$telegramId == nil)
            .sort(\.$fullName, .ascending)
            .all()) ?? []

        let data = employeePageData(all: all, page: page)
        await sendAdminInlineList(
            app: app,
            api: api,
            chatId: chatId,
            text: "Выберите сотрудника для привязки Telegram: (стр. \(data.page + 1)/\(data.totalPages))",
            data: data,
            callbackPrefix: "adm:link",
            editMessageId: editMessageId
        )

        var session = await sessions.get(chatId) ?? Session()
        session.state = .adminLinkChoose
        session.page = data.page
        await sessions.set(chatId, session)
    }

    static func showAdminEditNameEmployeesPage(
        app: Application,
        api: String,
        chatId: Int64,
        sessions: SessionStore,
        db: Database,
        page: Int,
        editMessageId: Int? = nil
    ) async {
        let all = (try? await Employee.query(on: db)
            .sort(\.$fullName, .ascending)
            .all()) ?? []

        let data = employeePageData(all: all, page: page)
        await sendAdminInlineList(
            app: app,
            api: api,
            chatId: chatId,
            text: "Выберите сотрудника для редактирования ФИО: (стр. \(data.page + 1)/\(data.totalPages))",
            data: data,
            callbackPrefix: "adm:edit",
            editMessageId: editMessageId
        )

        var session = await sessions.get(chatId) ?? Session()
        session.state = .adminEditNameChoose
        session.page = data.page
        await sessions.set(chatId, session)
    }

    static func showAdminTelegramBindEmployeesPage(
        app: Application,
        api: String,
        chatId: Int64,
        sessions: SessionStore,
        db: Database,
        page: Int,
        editMessageId: Int? = nil
    ) async {
        let all = (try? await Employee.query(on: db)
            .filter(\.$telegramId == nil)
            .sort(\.$fullName, .ascending)
            .all()) ?? []

        let data = employeePageData(all: all, page: page)
        await sendAdminInlineList(
            app: app,
            api: api,
            chatId: chatId,
            text: "Выберите сотрудника для привязки Telegram: (стр. \(data.page + 1)/\(data.totalPages))",
            data: data,
            callbackPrefix: "adm:bind",
            editMessageId: editMessageId
        )

        var session = await sessions.get(chatId) ?? Session()
        session.state = .adminTelegramBindChoose
        session.page = data.page
        await sessions.set(chatId, session)
    }

    static func showAdminTelegramChangeEmployeesPage(
        app: Application,
        api: String,
        chatId: Int64,
        sessions: SessionStore,
        db: Database,
        page: Int,
        editMessageId: Int? = nil
    ) async {
        let all = (try? await Employee.query(on: db)
            .filter(\.$telegramId != nil)
            .filter(\.$isActive == true)
            .sort(\.$fullName, .ascending)
            .all()) ?? []

        let data = employeePageData(all: all, page: page)
        await sendAdminInlineList(
            app: app,
            api: api,
            chatId: chatId,
            text: "Выберите сотрудника для изменения Telegram ID: (стр. \(data.page + 1)/\(data.totalPages))",
            data: data,
            callbackPrefix: "adm:change",
            editMessageId: editMessageId
        )

        var session = await sessions.get(chatId) ?? Session()
        session.state = .adminTelegramChangeChoose
        session.page = data.page
        await sessions.set(chatId, session)
    }

    private static func employeePageData(all: [Employee], page: Int) -> (slice: ArraySlice<Employee>, titleById: [UUID: String], page: Int, totalPages: Int) {
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

        return (slice: slice, titleById: titleById, page: p, totalPages: totalPages)
    }

    private static func sendAdminInlineList(
        app: Application,
        api: String,
        chatId: Int64,
        text: String,
        data: (slice: ArraySlice<Employee>, titleById: [UUID: String], page: Int, totalPages: Int),
        callbackPrefix: String,
        editMessageId: Int?
    ) async {
        let options = data.slice.compactMap { emp -> KeyboardBuilder.EmployeeInlineOption? in
            guard let id = try? emp.requireID() else { return nil }
            return .init(id: id, title: data.titleById[id] ?? emp.fullName)
        }
        let inline = KeyboardBuilder.employeesInlinePage(
            options: options,
            hasPrev: data.page > 0,
            hasNext: data.page < data.totalPages - 1,
            page: data.page,
            callbackPrefix: callbackPrefix
        )
        await sendOrEditInlineEmployeesList(
            app: app,
            api: api,
            chatId: chatId,
            text: text,
            inlineMarkup: inline,
            editMessageId: editMessageId
        )
    }
}
