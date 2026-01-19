//
//  PendingLinksScheduler.swift
//  ChatBot
//
//  Created by opencode on 20.01.2026.
//

import Vapor
import Fluent

struct PendingLinksScheduler {
    static func setup(app: Application) {
        app.logger.info("PendingLinksScheduler: initialized.")
        
        // Запускаем очистку каждые 10 минут
        app.eventLoopGroup.next().scheduleRepeatedTask(
            initialDelay: .seconds(30),
            delay: .minutes(10)
        ) { _ in
            Task {
                do {
                    let deletedCount = try await PendingLink.cleanupExpired(on: app.db)
                    if deletedCount > 0 {
                        app.logger.info("PendingLinksScheduler: cleaned up \(deletedCount) expired/used links.")
                    }
                } catch {
                    app.logger.error("PendingLinksScheduler cleanup error: \(error)")
                }
            }
        }
    }
}
