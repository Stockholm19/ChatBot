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
        let names = Array(slice.map { $0.fullName })
        
        await TelegramService.sendMessage(
            app, api: api, chatId: chatId,
            text: "Кому сказать спасибо?",
            replyMarkup: KeyboardBuilder.employeesPage(
                names: names,
                hasPrev: p > 0,
                hasNext: p < totalPages - 1
            )
        )
        await sessions.set(chatId, Session(state: .choosingEmployee, page: p))
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

    static func handleText(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        username: String?,
        text: String,
        sessions: SessionStore,
        db: Database
    ) async {
        
        // Игнорируем все сообщения из групп и каналов — бот отвечает только в личке
        if chatId <= 0 {
            return
        }
        
        let session = await sessions.get(chatId) ?? Session(state: .mainMenu)
        let state = session.state
        let currentTo = session.to
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = trimmed.normalizedNav

        // Debug: /whoami — показывает распознанный userId/username и env (только для админов)
        if trimmed == "/whoami" {
            guard isAdmin(userId: userId, username: username) else {
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
        case (.choosingEmployee, "⭠"), (.choosingEmployee, "<"), (.choosingEmployee, "⬅"), (.choosingEmployee, "←"):
            let page = (await sessions.get(chatId))?.page ?? 0
            await showEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: max(0, page - 1))
            return

        case (.choosingEmployee, "⭢"), (.choosingEmployee, ">"), (.choosingEmployee, "➡"), (.choosingEmployee, "→"):
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
            let name = trimmed
            if let emp = try? await Employee.query(on: db)
                .filter(\.$isActive == true)
                .filter(\.$fullName == name)
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
                await sessions.set(chatId, Session(state: .awaitingReason, to: nil, page: nil, chosenEmployeeId: empId))
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Напиши короткое сообщение, за что «\(emp.fullName)» получит благодарность. 🌟 (от \(minReasonLength) символов)",
                    replyMarkup: KeyboardBuilder.reasonMenu()
                )
                return
            } else {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Не нашёл такого сотрудника. Листай ◀/▶ или выбери из списка."
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

        case (.thanksMenu, "Количество переданных"):
            app.logger.info("BotMenu: tapped 'Количество переданных'")
            var total = 0
            if let tg = userId,
               let me = try? await Employee.query(on: db)
                   .filter(\.$telegramId == tg)
                   .first(),
               let meID = try? me.requireID() {
                total = (try? await Kudos.query(on: db)
                    .filter(\.$fromEmployee.$id == meID)
                    .count()) ?? 0
            }
            if total == 0 { // Fallback by normalized username
                let raw = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !raw.isEmpty {
                    let withAt = raw.hasPrefix("@") ? raw : "@\(raw)"
                    total = (try? await Kudos.query(on: db)
                        .group(.or) { or in
                            or.filter(\.$fromUsername == withAt)
                            or.filter(\.$fromUsername == raw)
                        }
                        .count()) ?? 0
                }
            }
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Ты отправил(а) <b>\(total)</b> «спасибо».",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
            )
            return

        case (.thanksMenu, "Количество полученных"):
            app.logger.info("BotMenu: tapped 'Количество полученных'")
            var total = 0
            if let tg = userId,
               let me = try? await Employee.query(on: db)
                   .filter(\.$telegramId == tg)
                   .first(),
               let meID = try? me.requireID() {
                total = (try? await Kudos.query(on: db)
                    .filter(\.$employee.$id == meID)
                    .count()) ?? 0
            }
            if total == 0 { // Fallback by normalized username (toUsername)
                let raw = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !raw.isEmpty {
                    let withAt = raw.hasPrefix("@") ? raw : "@\(raw)"
                    total = (try? await Kudos.query(on: db)
                        .group(.or) { or in
                            or.filter(\.$toUsername == withAt)
                            or.filter(\.$toUsername == raw)
                        }
                        .count()) ?? 0
                }
            }
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Ты получил(а) <b>\(total)</b> «спасибо».",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
            )
            return

        case (.thanksMenu, "Экспорт CSV") where isAdmin(userId: userId, username: username):

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
