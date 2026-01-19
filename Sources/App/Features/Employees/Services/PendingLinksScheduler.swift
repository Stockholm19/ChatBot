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
                    
                    // Очистка сотрудников без Telegram
                    try await self.cleanupUnlinkedEmployees(on: app.db, logger: app.logger)
                    
                } catch {
                    app.logger.error("PendingLinksScheduler cleanup error: \(error)")
                }
            }
        }
    }
    
    /// Удаление сотрудников без Telegram через 24 часа (если нет кудосов)
    private static func cleanupUnlinkedEmployees(on db: Database, logger: Logger) async throws {
        let threshold = Date().addingTimeInterval(-24 * 3600)
        
        let candidates = try await Employee.query(on: db)
            .filter(\.$isActive == true)
            .filter(\.$telegramId == nil)
            .filter(\.$createdAt < threshold)
            .all()
        
        var deletedCount = 0
        var skippedCount = 0
        
        for employee in candidates {
            guard let empId = employee.id else { continue }
            
            // Проверка наличия кудосов (полученных или отправленных)
            let kudosCount = try await Kudos.query(on: db)
                .group(.or) { or in
                    or.filter(\.$employee.$id == empId)
                    or.filter(\.$fromEmployee.$id == empId)
                }
                .count()
            
            if kudosCount == 0 {
                try await employee.delete(on: db)
                deletedCount += 1
            } else {
                logger.info("[Cleanup] Skipped employee \(employee.fullName) (\(empId)) due to existing kudos.")
                skippedCount += 1
            }
        }
        
        logger.info("unlinked_cleanup_candidates=\(candidates.count)")
        logger.info("unlinked_cleanup_deleted=\(deletedCount)")
        logger.info("unlinked_cleanup_skipped_with_kudos=\(skippedCount)")
    }
}
