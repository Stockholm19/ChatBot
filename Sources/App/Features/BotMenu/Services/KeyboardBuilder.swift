//
//  KeyboardBuilder.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 25.09.2025.
//

import Vapor
import Foundation

enum KeyboardBuilder {
    struct EmployeeInlineOption {
        let id: UUID
        let title: String
    }

    // Тексты кнопок главного меню — используются и в клавиатуре, и в роутинге
    enum MainMenuButton {
        static let sayThanks = "💌 Сказать спасибо"
        static let feed = "📜 Наши спасибо"
        static let jar = "🫙 Вспомнить"
        static let stats = "📊 Статистика"
        static let settings = "⚙️ Настройки"
    }

    /// Действие главного меню по тексту нажатой кнопки.
    /// Входящий текст роутер нормализует (`normalizedNav` убирает U+FE0F из «⚙️»),
    /// поэтому сравниваем тоже нормализованные заголовки.
    enum MainMenuAction: CaseIterable {
        case sayThanks, feed, jar, stats, settings

        var title: String {
            switch self {
            case .sayThanks: return MainMenuButton.sayThanks
            case .feed: return MainMenuButton.feed
            case .jar: return MainMenuButton.jar
            case .stats: return MainMenuButton.stats
            case .settings: return MainMenuButton.settings
            }
        }

        init?(text: String) {
            let normalized = text.normalizedNav
            guard let action = Self.allCases.first(where: { $0.title.normalizedNav == normalized }) else {
                return nil
            }
            self = action
        }
    }

    /// Единое главное меню: все основные действия на одном экране
    static func mainMenu(isAdmin: Bool) -> TgReplyKeyboard {
        var rows: [[TgReplyKeyboard.Button]] = [
            [ .init(text: MainMenuButton.sayThanks) ],
            [ .init(text: MainMenuButton.feed), .init(text: MainMenuButton.jar) ],
            [ .init(text: MainMenuButton.stats) ]
        ]
        if isAdmin { rows.append([ .init(text: MainMenuButton.settings) ]) }
        return TgReplyKeyboard(
            keyboard: rows,
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    static func statisticsMenu() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "📤 Выгрузить отправленные") ],
                [ .init(text: "📥 Выгрузить полученные") ],
                [ .init(text: "← Назад") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }
    
    static func adminMenu() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "👤 Добавить участника") ],
                [ .init(text: "🔁 Привязка Telegram") ],
                [ .init(text: "✏️ Изменить имя") ],
                [ .init(text: "🚫 Отключить участника") ],
                [ .init(text: "📁 Отключённые") ],
                [ .init(text: "📊 Экспорт CSV") ],
                [ .init(text: "← Назад") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    /// Постраничный список участников (по два имени в строке) + навигация
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

        // Навигация < / >
        var nav: [TgReplyKeyboard.Button] = []
        if hasPrev { nav.append(.init(text: "<")) }
        if hasNext { nav.append(.init(text: ">")) }
        if !nav.isEmpty { rows.append(nav) }

        // Кнопка назад
        rows.append([ .init(text: "← Назад") ])

        return TgReplyKeyboard(
            keyboard: rows,
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    static func employeesInlinePage(
        options: [EmployeeInlineOption],
        hasPrev: Bool,
        hasNext: Bool,
        page: Int,
        callbackPrefix: String
    ) -> TgInlineKeyboardMarkup {
        var rows: [[TgInlineKeyboardMarkup.Button]] = []

        var i = 0
        while i < options.count {
            if i + 1 < options.count {
                rows.append([
                    .init(text: options[i].title, callback_data: "\(callbackPrefix):pick:\(options[i].id.uuidString)"),
                    .init(text: options[i + 1].title, callback_data: "\(callbackPrefix):pick:\(options[i + 1].id.uuidString)")
                ])
                i += 2
            } else {
                rows.append([
                    .init(text: options[i].title, callback_data: "\(callbackPrefix):pick:\(options[i].id.uuidString)")
                ])
                i += 1
            }
        }

        var nav: [TgInlineKeyboardMarkup.Button] = []
        if hasPrev { nav.append(.init(text: "<", callback_data: "\(callbackPrefix):page:\(page - 1)")) }
        if hasNext { nav.append(.init(text: ">", callback_data: "\(callbackPrefix):page:\(page + 1)")) }
        if !nav.isEmpty { rows.append(nav) }

        rows.append([.init(text: "← Назад", callback_data: "\(callbackPrefix):back")])
        return TgInlineKeyboardMarkup(inline_keyboard: rows)
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

    /// Клавиатура на шаге ввода текста: «Назад» (если был выбор из списка) и «Отмена»
    static func reasonMenu(showBack: Bool = true) -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                showBack
                    ? [ .init(text: "← Назад"), .init(text: "Отмена") ]
                    : [ .init(text: "Отмена") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }
    
    /// Клавиатура для возврата к списку участников
    static func backToEmployeesList() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "← Назад к списку") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }
    
    // MARK: - Admin Keyboards

    static func back() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "← Назад") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    /// Клавиатура шага привязки Telegram при добавлении участника (админка)
    static func adminAddForwardMenu() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "🔗 Привязать через код") ],
                [ .init(text: "← Назад") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    static func adminArchiveActionsMenu() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "✅ Восстановить") ],
                [ .init(text: "🗑 Удалить совсем") ],
                [ .init(text: "← Назад") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }
    
    static func yesNo() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "Да"), .init(text: "Нет") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: true
        )
    }
    
    static func yesNoCancel() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "Да"), .init(text: "Нет") ],
                [ .init(text: "Отмена") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: true
        )
    }

    /// Клавиатура для меню привязки Telegram (админка)
    static func adminTelegramMenu() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "➕ Привязать Telegram") ],
                [ .init(text: "🔄 Изменить Telegram") ],
                [ .init(text: "← Назад") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    /// Клавиатура для меню ожидания форварда (привязка/изменение Telegram)
    static func adminTelegramForwardMenuBind() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "🔗 Получить код") ],
                [ .init(text: "Отмена") ],
                [ .init(text: "← Назад") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    static func adminTelegramForwardMenuChange() -> TgReplyKeyboard {
        TgReplyKeyboard(
            keyboard: [
                [ .init(text: "🔗 Получить код") ],
                [ .init(text: "← Назад") ]
            ],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    // MARK: - Reactions

    /// Варианты реакций на полученное спасибо (индекс уходит в callback_data)
    static let reactions = ["❤️", "🤗", "🥹"]

    /// Инлайн-кнопки реакций под уведомлением о новом спасибо
    static func reactionsInline(kudosId: UUID) -> TgInlineKeyboardMarkup {
        let buttons = reactions.enumerated().map { index, emoji in
            TgInlineKeyboardMarkup.Button(text: emoji, callback_data: "react:\(index):\(kudosId.uuidString)")
        }
        return TgInlineKeyboardMarkup(inline_keyboard: [buttons])
    }
}
