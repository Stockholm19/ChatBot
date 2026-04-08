//
//  BotController.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 25.09.2025.
//

import Vapor
import Fluent

/// Единая точка обработки входящих апдейтов Telegram.
/// Делегирует навигацию в BotMenu и доменные действия в соответствующие фичи.
enum BotController {

    /// Обработка одного входящего сообщения
    static func handle(app: Application, message m: TgMessage, api: String, sessions: SessionStore) async {
        let chatId = m.chat.id
        let text = (m.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // 0) Обработка команды /link (до всех проверок доступа)
        let lower = text.lowercased()
        if lower.hasPrefix("/link") {
            await handleLinkCommand(app: app, message: m, api: api, db: app.db)
            return
        }

        // --- Начало проверки доступа ---
        // Проверяем, есть ли у пользователя telegramId
        guard let userId = m.from?.id else {
            // Если ID нет, вежливо отказываем в доступе
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "К сожалению, я не могу определить ваш профиль. Доступ ограничен.")
            app.logger.warning("Access denied: missing Telegram user ID.")
            return
        }

        // Сначала проверяем, не является ли пользователь админом.
        // Админы получают доступ, даже если их нет в списке сотрудников.
        if BotMenuController.isAdmin(userId: userId, username: m.from?.username) {
            app.logger.info("Admin access granted for user: \(userId)")
        } else {
            // Если не админ, ищем сотрудника в базе по telegramId
            do {
                let employee = try await Employee.query(on: app.db)
                    .filter(\.$telegramId == userId)
                    .filter(\.$isActive == true)
                    .first()

                // Если сотрудник не найден или неактивен, отказываем в доступе
                guard employee != nil else {
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "К сожалению, доступ к боту ограничен только для сотрудников.")
                    app.logger.info("Access denied for non-employee or inactive user: \(userId)")
                    return
                }
            } catch {
                // В случае ошибки с базой данных, тоже отказываем
                app.logger.error("Database error during employee check: \(error.localizedDescription)")
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Произошла внутренняя ошибка. Пожалуйста, попробуйте позже.")
                return
            }
        }
        // --- Конец проверки доступа ---


        // 1) Стартовое меню
        if text == "/start" {
            await BotMenuController.handleStart(app: app, api: api, chatId: chatId, sessions: sessions)
            return
        }

        // 2) Передаём остальной текст в BotMenu (подменю, шаги сценариев)
        await BotMenuController.handleMessage(
            app: app,
            api: api,
            chatId: chatId,
            userId: m.from?.id,
            username: m.from?.username,
            message: m,
            sessions: sessions,
            db: app.db
        )
    }

    /// Обработка callback_query от Inline Keyboard
    static func handleCallback(app: Application, query q: TgCallbackQuery, api: String, sessions: SessionStore) async {
        guard let callbackMessage = q.message else {
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: q.id)
            return
        }

        let chatId = callbackMessage.chat.id
        guard chatId > 0 else {
            await TelegramService.answerCallbackQuery(app, api: api, callbackQueryId: q.id)
            return
        }

        let userId = q.from.id
        if BotMenuController.isAdmin(userId: userId, username: q.from.username) {
            app.logger.info("Admin callback access granted for user: \(userId)")
        } else {
            do {
                let employee = try await Employee.query(on: app.db)
                    .filter(\.$telegramId == userId)
                    .filter(\.$isActive == true)
                    .first()

                guard employee != nil else {
                    await TelegramService.answerCallbackQuery(
                        app,
                        api: api,
                        callbackQueryId: q.id,
                        text: "Доступ ограничен только для сотрудников.",
                        showAlert: true
                    )
                    app.logger.info("Callback access denied for non-employee or inactive user: \(userId)")
                    return
                }
            } catch {
                app.logger.error("Database error during callback employee check: \(error.localizedDescription)")
                await TelegramService.answerCallbackQuery(
                    app,
                    api: api,
                    callbackQueryId: q.id,
                    text: "Внутренняя ошибка. Попробуйте позже.",
                    showAlert: true
                )
                return
            }
        }

        await BotMenuController.handleCallback(
            app: app,
            api: api,
            query: q,
            sessions: sessions,
            db: app.db
        )
    }

    /// Обработка команды /link <code>
    private static func handleLinkCommand(app: Application, message m: TgMessage, api: String, db: Database) async {
        let chatId = m.chat.id
        // Команда доступна только в личном чате с ботом
        if chatId <= 0 {
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Команда /link доступна только в личном чате с ботом.")
            return
        }
        guard let fromId = m.from?.id else {
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Ошибка: не удалось определить ваш Telegram ID.")
            return
        }

        let parts = (m.text ?? "").split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 2 else {
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Используй: <code>/link 123456</code>")
            return
        }

        // parts[0] может быть "/link" или "/link@BotName" - нам важен только код
        let code = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        app.logger.info("link_attempt: fromId=\(fromId), code=\(code)")

        do {
            guard let pending = try await PendingLink.query(on: db)
                .filter(\.$code == code)
                .with(\.$employee)
                .first() else {
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Код не найден или устарел. Попроси админа создать новый.")
                app.logger.warning("link_failed_not_found: fromId=\(fromId), code=\(code)")
                return
            }

            if pending.isUsed {
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Этот код уже использован.")
                app.logger.warning("link_failed_used: fromId=\(fromId), code=\(code)")
                return
            }

            if pending.expiresAt < Date() {
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Код истек. Попроси админа создать новый.")
                app.logger.warning("link_failed_expired: fromId=\(fromId), code=\(code)")
                return
            }

            let employee = pending.employee
            let employeeId = try employee.requireID()

            // Проверка конфликтов
            
            // 1. Если этот Telegram ID уже привязан к ДРУГОМУ сотруднику
            let existingWithId = try await Employee.query(on: db)
                .filter(\.$telegramId == fromId)
                .first()
            
            if let existing = existingWithId, try existing.requireID() != employeeId {
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Этот Telegram уже привязан к другому сотруднику. Обратись к администратору.")
                app.logger.warning("link_failed_conflict_tg: fromId=\(fromId), employeeId=\(employeeId)")
                return
            }

            // 2. Проверка состояния текущего сотрудника
            if let currentTgId = employee.telegramId {
                if currentTgId == fromId {
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Твой аккаунт уже привязан. Можешь пользоваться ботом!")
                    // Закрываем pending как успех
                    pending.isUsed = true
                    pending.usedAt = Date()
                    try await pending.save(on: db)
                    return
                } else {
                    await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "К этому сотруднику уже привязан другой Telegram ID. Обратись к администратору.")
                    app.logger.warning("link_failed_conflict_emp: fromId=\(fromId), employeeId=\(employeeId), existingTg=\(currentTgId)")
                    return
                }
            }

            // Выполняем привязку (атомарно)
            let pendingId = try pending.requireID()
            let now = Date()
            try await db.transaction { tx in
                guard let empInTx = try await Employee.find(employeeId, on: tx) else {
                    throw Abort(.notFound, reason: "Employee not found")
                }
                guard let pendingInTx = try await PendingLink.find(pendingId, on: tx) else {
                    throw Abort(.notFound, reason: "PendingLink not found")
                }

                empInTx.telegramId = fromId
                empInTx.isActive = true
                try await empInTx.save(on: tx)

                pendingInTx.isUsed = true
                pendingInTx.usedAt = now
                try await pendingInTx.save(on: tx)
            }

            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Готово! Твой аккаунт привязан. Теперь ты можешь пользоваться всеми функциями бота.")
            app.logger.info("link_success: fromId=\(fromId), employeeId=\(employeeId)")

            // Уведомляем админа
            if let adminId = pending.createdByAdminTgId {
                let adminMsg = "✅ Сотрудник <b>\(employee.fullName)</b> успешно привязал свой Telegram."
                await TelegramService.sendMessage(app, api: api, chatId: adminId, text: adminMsg)
            }

        } catch {
            app.logger.error("link_error: \(error)")
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Произошла ошибка при привязке. Попробуй позже.")
        }
    }
}
