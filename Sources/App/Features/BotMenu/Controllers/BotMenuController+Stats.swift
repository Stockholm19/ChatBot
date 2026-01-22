//
//  BotMenuController+Stats.swift
//  ChatBot
//

import Vapor
import Fluent

extension BotMenuController {
    
    static func handleStatsState(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        username: String?,
        sessions: SessionStore,
        db: Database,
        text: String,
        isUserAdmin: Bool
    ) async {
        switch text {
        case "← Назад":
            await sessions.set(chatId, Session(state: .thanksMenu))
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Меню благодарностей:",
                replyMarkup: KeyboardBuilder.thanksMenu(isAdmin: isUserAdmin)
            )

        case "Моя статистика":
            var sentTotal = 0
            var receivedTotal = 0
            if let tg = userId,
               let me = try? await Employee.query(on: db)
                   .filter(\.$telegramId == tg)
                   .first(),
               let meID = try? me.requireID() {

                sentTotal = (try? await Kudos.query(on: db)
                    .filter(\.$fromEmployee.$id == meID)
                    .count()) ?? 0

                receivedTotal = (try? await Kudos.query(on: db)
                    .filter(\.$employee.$id == meID)
                    .count()) ?? 0
            }
            let msg = "Твоя статистика:\nОтправлено: \(sentTotal)\nПолучено: \(receivedTotal)"
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: msg,
                replyMarkup: KeyboardBuilder.statisticsMenu()
            )

        case "Экспорт переданных":
            var rows: [Kudos] = []
            if let tg = userId,
               let me = try? await Employee.query(on: db)
                   .filter(\.$telegramId == tg)
                   .first(),
               let meID = try? me.requireID() {

                rows = (try? await Kudos.query(on: db)
                    .filter(\.$fromEmployee.$id == meID)
                    .sort(\.$ts, .descending)
                    .all()) ?? []
            }

            if rows.isEmpty {
                let raw = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !raw.isEmpty {
                    let withAt = raw.hasPrefix("@") ? raw : "@\(raw)"
                    rows = (try? await Kudos.query(on: db)
                        .group(.or) { or in
                            or.filter(\.$fromUsername == withAt)
                            or.filter(\.$fromUsername == raw)
                        }
                        .sort(\.$ts, .descending)
                        .all()) ?? []
                }
            }

            if rows.isEmpty {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "У тебя пока нет отправленных «спасибо» для экспорта.",
                    replyMarkup: KeyboardBuilder.statisticsMenu()
                )
                return
            }

            let uniqueFilename = "kudos_sent_\(UUID().uuidString).csv"
            let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFilename).path

            defer { try? FileManager.default.removeItem(atPath: tmpPath) }

            do {
                try await CSVExporter.exportKudos(db: db, rows: rows, to: tmpPath)
                try await TelegramService.sendDocument(
                    app, api: api, chatId: chatId,
                    filePath: tmpPath,
                    caption: "Экспорт отправленных благодарностей"
                )
            } catch {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Не получилось создать или отправить экспорт отправленных благодарностей.",
                    replyMarkup: KeyboardBuilder.statisticsMenu()
                )
            }

        case "Экспорт полученных":
            var rows: [Kudos] = []
            if let tg = userId,
               let me = try? await Employee.query(on: db)
                   .filter(\.$telegramId == tg)
                   .first(),
               let meID = try? me.requireID() {

                rows = (try? await Kudos.query(on: db)
                    .filter(\.$employee.$id == meID)
                    .sort(\.$ts, .descending)
                    .all()) ?? []
            }

            if rows.isEmpty {
                let raw = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !raw.isEmpty {
                    let withAt = raw.hasPrefix("@") ? raw : "@\(raw)"
                    rows = (try? await Kudos.query(on: db)
                        .group(.or) { or in
                            or.filter(\.$toUsername == withAt)
                            or.filter(\.$toUsername == raw)
                        }
                        .sort(\.$ts, .descending)
                        .all()) ?? []
                }
            }

            if rows.isEmpty {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "У тебя пока нет полученных «спасибо» для экспорта.",
                    replyMarkup: KeyboardBuilder.statisticsMenu()
                )
                return
            }

            let uniqueFilename = "kudos_received_\(UUID().uuidString).csv"
            let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFilename).path

            defer { try? FileManager.default.removeItem(atPath: tmpPath) }

            do {
                try await CSVExporter.exportKudos(db: db, rows: rows, to: tmpPath)
                try await TelegramService.sendDocument(
                    app, api: api, chatId: chatId,
                    filePath: tmpPath,
                    caption: "Экспорт полученных благодарностей"
                )
            } catch {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Не получилось создать или отправить экспорт полученных благодарностей.",
                    replyMarkup: KeyboardBuilder.statisticsMenu()
                )
            }

        default:
            break
        }
    }
}
