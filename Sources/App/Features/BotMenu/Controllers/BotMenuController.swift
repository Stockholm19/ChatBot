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

    /// Проверка прав администратора: поддерживает и ADMIN_IDS (числовые Telegram ID),
    /// и ADMIN_USERNAMES (ники без @). Достаточно совпадения по одному из списков.
    static func isAdmin(userId: Int64?, username: String?) -> Bool {
        var ok = false
        if let id = userId {
            let rawIDs = (Environment.get("ADMIN_IDS") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ids = Set(rawIDs.split(separator: ",").compactMap {
                Int64($0.trimmingCharacters(in: .whitespacesAndNewlines))
            })
            ok = ok || ids.contains(id)
        }
        if let u = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            let rawUN = (Environment.get("ADMIN_USERNAMES") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let uns = Set(rawUN.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            })
            ok = ok || uns.contains(u)
        }
        return ok
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
        userId: Int64?,
        username: String?,
        text: String,
        sessions: SessionStore,
        db: Database
    ) async {
        let state = (await sessions.get(chatId))?.state ?? .mainMenu

        // Debug: /whoami — показывает распознанный userId/username и env (только для админов)
        // Как проверка норм ли читает .env
        if text == "/whoami" {
            guard isAdmin(userId: userId, username: username) else {
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Команда недоступна.")
                return
            }
            let msg = """
            userId: \(userId.map(String.init) ?? "nil")
            username: \(username ?? "nil")
            ADMIN_IDS: \(Environment.get("ADMIN_IDS") ?? "(nil)")
            ADMIN_USERNAMES: \(Environment.get("ADMIN_USERNAMES") ?? "(nil)")
            isAdmin: \(isAdmin(userId: userId, username: username) ? "true" : "false")
            """
            await TelegramService.sendMessage(app, api: api, chatId: chatId, text: msg)
            return
        }

        switch (state, text) {

        // MARK: Главное меню → подменю «Спасибо»
        case (.mainMenu, "Передать спасибо"):
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
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
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
            )
            return

        case (.thanksMenu, "Экспорт CSV") where isAdmin(userId: userId, username: username):
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
                fromUserId: userId ?? 0,
                fromUsername: fromUsername,
                fromName: username ?? fromUsername,
                toUsername: toUsername,
                reason: text
            )
            try? await kudos.save(on: db)

            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Готово! Отправлено \(toUsername).",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isAdmin(userId: userId, username: username))
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
