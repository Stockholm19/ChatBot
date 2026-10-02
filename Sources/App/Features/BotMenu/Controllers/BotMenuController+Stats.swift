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
            await showMainMenu(app: app, api: api, chatId: chatId, sessions: sessions, isUserAdmin: isUserAdmin)

        case "📤 Выгрузить отправленные":
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
                    text: "Ты пока не отправлял(а) спасибо — выгружать нечего 🙂",
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
                    caption: "Все спасибо, которые ты отправил(а) 💌"
                )
            } catch {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Не получилось сделать выгрузку отправленных спасибо. Попробуй позже.",
                    replyMarkup: KeyboardBuilder.statisticsMenu()
                )
            }

        case "📥 Выгрузить полученные":
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
                    text: "Тебе пока не приходили спасибо — выгружать нечего 🙂",
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
                    caption: "Все спасибо, которые ты получил(а) 💛"
                )
            } catch {
                await TelegramService.sendMessage(
                    app, api: api, chatId: chatId,
                    text: "Не получилось сделать выгрузку полученных спасибо. Попробуй позже.",
                    replyMarkup: KeyboardBuilder.statisticsMenu()
                )
            }

        default:
            break
        }
    }

    /// Показывает личную статистику и открывает меню выгрузок
    static func showPersonalStats(
        app: Application,
        api: String,
        chatId: Int64,
        userId: Int64?,
        sessions: SessionStore,
        db: Database
    ) async {
        await sessions.set(chatId, Session(state: .statisticsMenu))

        guard let me = await currentParticipant(userId: userId, db: db),
              let meID = me.id,
              let stats = try? await KudosService(db: db).stats(for: meID) else {
            await TelegramService.sendMessage(
                app, api: api, chatId: chatId,
                text: "Статистики пока нет: твой Telegram не привязан к участнику.",
                replyMarkup: KeyboardBuilder.statisticsMenu()
            )
            return
        }

        await TelegramService.sendMessage(
            app, api: api, chatId: chatId,
            text: formatStats(stats),
            replyMarkup: KeyboardBuilder.statisticsMenu()
        )
    }

    static func formatStats(_ stats: KudosService.PersonalStats) -> String {
        """
        📊 <b>Твоя статистика</b>

        💌 Отправлено: \(stats.sentTotal) (за неделю: \(stats.sentLastWeek))
        💛 Получено: \(stats.receivedTotal) (за неделю: \(stats.receivedLastWeek))
        🤗 Ответов-реакций на твои спасибо: \(stats.reactionsOnSent)
        """
    }
}
