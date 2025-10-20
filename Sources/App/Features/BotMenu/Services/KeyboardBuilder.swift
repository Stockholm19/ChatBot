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
            [ .init(text: "Количество переданных") ],
            [ .init(text: "Сколько получил") ]
        ]
        if isAdmin { rows.append([ .init(text: "Экспорт CSV") ]) }
        rows.append([ .init(text: "← Назад") ])
        return TgReplyKeyboard(
            keyboard: rows,
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    /// Клавиатура выбора получателя: только «Назад»
    static func chooseRecipientMenu() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "← Назад") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    /// Клавиатура на шаге ввода причины: «Назад» и «Отмена»
    static func reasonMenu() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "← Назад"), .init(text: "Отмена") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }
}
