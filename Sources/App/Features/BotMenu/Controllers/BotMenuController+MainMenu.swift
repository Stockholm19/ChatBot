//
//  BotMenuController+MainMenu.swift
//  ChatBot
//

import Vapor
import Fluent

extension BotMenuController {
    
    static func handleMainMenu(
        app: Application,
        api: String,
        chatId: Int64,
        text: String,
        sessions: SessionStore,
        isUserAdmin: Bool
    ) async {
        switch text {
        case "Передать спасибо":
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isUserAdmin)
            )
            await sessions.set(chatId, Session(state: .thanksMenu, to: nil))
            
        default:
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Не понял команду. Нажми кнопку ниже.",
                replyMarkup: KeyboardBuilder.mainMenu()
            )
            await sessions.set(chatId, Session(state: .mainMenu))
        }
    }
}
