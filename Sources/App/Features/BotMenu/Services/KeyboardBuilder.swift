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
            [ .init(text: "Кому из коллег хочешь сказать спасибо?") ],
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

    /// Постраничный список сотрудников (по два имени в строке) + навигация
    static func employeesPage(names: [String], hasPrev: Bool, hasNext: Bool) -> TgReplyKeyboard {
        // Сетка 2×N: группируем имена по две кнопки в ряд
        var rows: [[TgReplyKeyboard.Button]] = []
        var i = 0
        while i < names.count {
            if i + 1 < names.count {
                rows.append([ .init(text: names[i]), .init(text: names[i+1]) ])
                i += 2
            } else {
                rows.append([ .init(text: names[i]) ])
                i += 1
            }
        }

        // Навигация ◀ / ▶ ("чистые" символы без FE0E/FE0F)
        var nav: [TgReplyKeyboard.Button] = []
        if hasPrev { nav.append(.init(text: "◀")) }
        if hasNext { nav.append(.init(text: "▶")) }
        if !nav.isEmpty { rows.append(nav) }

        // Кнопка назад
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
