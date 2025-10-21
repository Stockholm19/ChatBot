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

    /// Постраничный список сотрудников (по одному имени в строке) + навигация
    static func employeesPage(names: [String], hasPrev: Bool, hasNext: Bool) -> TgReplyKeyboard {
        var rows: [[TgReplyKeyboard.Button]] = names.map { [ .init(text: $0) ] }

        // Навигация ◀︎ / ▶︎
        var nav: [TgReplyKeyboard.Button] = []
        if hasPrev { nav.append(.init(text: "◀︎")) }
        if hasNext { nav.append(.init(text: "▶︎")) }
        if !nav.isEmpty { rows.append(nav) }

        // Фолбэк ручного ввода и назад
//        rows.append([ .init(text: "Ввести @username вручную") ]) // скрыл поиск по нику, раз сделал по Фамилии и имени
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
    
    /// Клавиатура для возврата к списку сотрудников
    static func backToEmployeesList() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "← Назад к списку") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }
}
