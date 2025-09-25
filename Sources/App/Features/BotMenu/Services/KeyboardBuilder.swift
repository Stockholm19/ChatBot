//
//  KeyboardBuilder.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 25.09.2025.
//

import Vapor

enum KeyboardBuilder {
    static func mainMenu() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [[ .init(text: "Передать спасибо") ]],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    static func thanksMenu(isAdmin: Bool) -> TgReplyKeyboard {
        var rows: [[TgReplyKeyboard.Button]] = [
            [ .init(text: "Спасибо") ],
            [ .init(text: "Количество переданных") ]
        ]
        if isAdmin { rows.append([ .init(text: "Экспорт CSV") ]) }
        rows.append([ .init(text: "← Назад") ])
        return TgReplyKeyboard(keyboard: rows, resize_keyboard: true, one_time_keyboard: false)
    }
}
