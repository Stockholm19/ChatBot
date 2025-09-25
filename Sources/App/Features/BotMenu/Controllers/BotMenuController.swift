//
//  BotMenuController.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 25.09.2025.
//

import Vapor
import Fluent

enum BotMenuController {

    // MARK: - Roles

    static func isAdmin(_ username: String?) -> Bool {
        guard let u = username?.lowercased() else { return false }
        let raw = Environment.get("ADMIN_USERNAMES") ?? "" // пример: "roman,teamlead,hr"
        let set = Set(
            raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        )
        return set.contains(u)
    }

    // MARK: - Entry points

    static func handleStart(
        app: Application,
        api: String,
        chatId: Int64,
        sessions: SessionStore
    ) async {
        await TelegramService.sendMessage(
            app, api: api, chatId: chatId,
            text: "Привет! Выбирай действие:",
            replyMarkup: KeyboardBuilder.mainMenu()
        )
        await sessions.set(chatId, Session(state: .mainMenu, to: nil))
    }

    static func handleText(
        app: Application,
        api: String,
        chatId: Int64,
        username: String?,
        text: String,
        sessions: SessionStore,
        db: Database
    ) async {
        let state = (await sessions.get(chatId))?.state ?? .mainMenu

        switch (state, text) {

        // MARK: Главное меню → подменю «Спасибо»
        case (.mainMenu, "Передать спасибо"):
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(username))
            )
            await sessions.set(chatId, Session(state: .thanksMenu, to: nil))
            return

        // MARK: Подменю «Спасибо» — запустить сценарий
        case (.thanksMenu, "Спасибо"):
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Кому сказать спасибо? Пришли @username получателя."
            )
            await sessions.set(chatId, Session(state: .awaitingRecipient))
            return

        case (.thanksMenu, "Количество переданных"):
            let me = "@\(username ?? "")"
            let total = (try? await Kudos.query(on: db)
                .filter(\.$fromUsername == me)
                .count()) ?? 0
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Ты отправил благодарностей: <b>\(total)</b>.",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(username))
            )
            return

        case (.thanksMenu, "Экспорт CSV") where isAdmin(username):
            // Путь во временную папку
            let tmpPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("kudos_export.csv").path
            // Экспорт и отправка файла
            try? await CSVExporter.exportKudos(db: db, to: tmpPath)
            try? await TelegramService.sendDocument(
                app, api: api, chatId: chatId,
                filePath: tmpPath,
                caption: "Экспорт благодарностей"
            )
            return

        case (.thanksMenu, "← Назад"):
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Главное меню:",
                replyMarkup: KeyboardBuilder.mainMenu()
            )
            await sessions.set(chatId, Session(state: .mainMenu))
            return

        // MARK: Шаги сценария: получатель → причина

        // Принят @username получателя
        case (.awaitingRecipient, _) where text.hasPrefix("@"):
            await sessions.set(chatId, Session(state: .awaitingReason, to: text))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "За что благодаришь? Одно сообщение (≥ 20 символов)."
            )
            return

        // Принята причина (валидная длина) → сохраняем
        case (.awaitingReason, _) where text.count >= 20:
            let fromUsername = "@\(username ?? "unknown")"
            let toUsername = (await sessions.get(chatId))?.to ?? "@unknown"

            let kudos = Kudos(
                ts: Date(),
                fromUserId: 61087823, // Реальный Telegram userId для Админов
                fromUsername: fromUsername,
                fromName: username ?? fromUsername,
                toUsername: toUsername,
                reason: text
            )
            try? await kudos.save(on: db)

            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Готово! Отправлено \(toUsername).",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(username))
            )
            await sessions.set(chatId, Session(state: .thanksMenu, to: nil))
            return

        // MARK: Фолбэк
        default:
            // Мягкая подсказка на случай непредусмотренного ввода
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Не понял команду. Нажми кнопку ниже.",
                replyMarkup: KeyboardBuilder.mainMenu()
            )
            await sessions.set(chatId, Session(state: .mainMenu))
            return
        }
    }
}
