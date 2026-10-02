//
//  BotMenuController+AdminMenu.swift
//  ChatBot
//

import Vapor
import Fluent

extension BotMenuController {

    // MARK: - Shared admin texts

    static let askNameText = "Как подписывать нового участника? Можно имя или ласковое прозвище — так оно будет видно в боте."

    static func bindPromptText(name: String) -> String {
        """
        Участник: \(name.htmlEscaped)
        Telegram ещё не привязан. Перешли любое сообщение от этого человека.
        Если в пересылках профиль скрыт — нажми «🔗 Получить код» и отправь ему приглашение.
        """
    }

    static func changePromptText(name: String, currentTgText: String) -> String {
        """
        Участник: \(name.htmlEscaped)
        \(currentTgText)

        Перешли сообщение с нового аккаунта.
        Если в пересылках профиль скрыт — нажми «🔗 Получить код».
        """
    }

    static func telegramConflictText(name: String) -> String {
        "Этот Telegram уже привязан к участнику \(name.htmlEscaped).\nВыбери другой аккаунт или сначала измени привязку у \(name.htmlEscaped)."
    }
    
    static func handleAdminMenuState(
        app: Application,
        api: String,
        chatId: Int64,
        text: String,
        sessions: SessionStore,
        db: Database,
        isUserAdmin: Bool
    ) async {
        guard isUserAdmin else { return }
        
        switch text {
        case "📊 Экспорт CSV":
            let uniqueFilename = "kudos_export_\(UUID().uuidString).csv"
            let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFilename).path
            defer { try? FileManager.default.removeItem(atPath: tmpPath) }
            
            do {
                try await CSVExporter.exportKudos(db: db, to: tmpPath)
                try await TelegramService.sendDocument(
                    app, api: api, chatId: chatId,
                    filePath: tmpPath,
                    caption: "Все спасибо в одном файле 📊"
                )
            } catch {
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Не удалось создать или отправить экспорт. Пожалуйста, проверьте логи.")
            }

        case "← Назад":
            await showMainMenu(app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin)

        default:
            if text.contains("Добавить участника") {
                await sessions.set(chatId, Session(state: .adminAddAskName))
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: Self.askNameText,
                    replyMarkup: KeyboardBuilder.back()
                )
            } else if text.contains("Привязка Telegram") {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Выберите действие:",
                    replyMarkup: KeyboardBuilder.adminTelegramMenu()
                )
                var session = await sessions.get(chatId) ?? Session()
                session.state = .adminTelegramMenu
                await sessions.set(chatId, session)
            } else if text.contains("Изменить имя") {
                await showAdminEditNameEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0)
            } else if text.contains("Отключить участника") {
                await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0, active: true, targetState: .adminDeactivateChoose)
            } else if text.contains("Отключённые") {
                await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0, active: false, targetState: .adminArchiveChoose)
            }
        }
    }
}
