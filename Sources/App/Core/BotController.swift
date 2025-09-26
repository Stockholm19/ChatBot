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
