//
//  BotMenuController+AdminMenu.swift
//  ChatBot
//

import Vapor
import Fluent

extension BotMenuController {
    
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
                    caption: "Экспорт благодарностей"
                )
            } catch {
                await TelegramService.sendMessage(app, api: api, chatId: chatId, text: "Не удалось создать или отправить экспорт. Пожалуйста, проверьте логи.")
            }

        case "← Назад":
            await sessions.set(chatId, Session(state: .thanksMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isUserAdmin)
            )

        default:
            if text.contains("Добавить сотрудника") {
                await sessions.set(chatId, Session(state: .adminAddAskName))
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Введи Фамилию и Имя (например: Иванов Иван)",
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
            } else if text.contains("Редактировать ФИО") {
                await showAdminEditNameEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0)
            } else if text.contains("Деактивировать сотрудника") {
                await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0, active: true, targetState: .adminDeactivateChoose)
            } else if text.contains("Архив сотрудников") {
                await showAdminEmployeesPage(app: app, api: api, chatId: chatId, sessions: sessions, db: db, page: 0, active: false, targetState: .adminArchiveChoose)
            }
        }
    }
}
