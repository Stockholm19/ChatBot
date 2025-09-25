//
//  KeyboardBuilder.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 25.09.2025.
//

import Vapor

struct TgReplyKeyboard: Content {
    struct Button: Content { let text: String }
    let keyboard: [[Button]]
    let resize_keyboard: Bool
    let one_time_keyboard: Bool
}

enum KeyboardBuilder {
    static func mainMenu() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [.init(text: "Передать спасибо")],
                // сюда позже добавить: [.init(text: "Справочник"), .init(text: "Кто за что отвечает")]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    static func thanksMenu(isAdmin: Bool) -> TgReplyKeyboard {
        var rows: [[TgReplyKeyboard.Button]] = [
            [.init(text: "Спасибо")],
            [.init(text: "Количество переданных")]
        ]
        if isAdmin { rows.append([.init(text: "Экспорт CSV")]) }
        rows.append([.init(text: "← Назад")])
        return TgReplyKeyboard(keyboard: rows, resize_keyboard: true, one_time_keyboard: false)
    }
}
