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
        await BotMenuController.handleText(
            app: app,
            api: api,
            chatId: chatId,
            userId: m.from?.id,
            username: m.from?.username,
            text: text,
            sessions: sessions,
            db: app.db
        )
    }
}
