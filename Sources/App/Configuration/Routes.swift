//
//  Routes.swift
//  kudos-vapor
//
//  Created by Роман Пшеничников on 23.09.2025.
//

import Vapor
import Fluent
import SQLKit

public func routes(_ app: Application) throws {
    try app.kudosRoutes()
    try app.exportRoutes()

    // Простой healthcheck (для Docker/Load Balancer)
    app.get("health") { _ in "ok" }

    // Расширенный healthcheck: HTTP + БД + состояние Telegram polling-loop.
    app.get("healthz") { req async throws -> Response in
        var dbOK = false

        do {
            if let sql = req.db as? SQLDatabase {
                // Дешёвый пинг БД
                try await sql.raw("SELECT 1").run()
                dbOK = true
            } else {
                // Драйвер БД не предоставляет SQLDatabase (например, нет SQLKit)
                dbOK = false
            }
        } catch {
            req.logger.warning("Health DB check failed: \(error.localizedDescription)")
            dbOK = false
        }

        let staleSeconds = healthEnvInt(name: "POLLING_STALE_SECONDS", defaultValue: 120)
        let startupGraceSeconds = healthEnvInt(name: "HEALTH_STARTUP_GRACE_SECONDS", defaultValue: 120)

        let pollingSnapshot = await req.application.pollingHealthStore.snapshot()
        let now = Date()
        let startupGraceActive = now.timeIntervalSince(pollingSnapshot.startedAt) < Double(startupGraceSeconds)

        let pollLagSec = pollingSnapshot.lastSuccessfulPollAt.map {
            max(0, Int(now.timeIntervalSince($0)))
        }

        let pollingOK: Bool
        if let pollLagSec {
            pollingOK = pollLagSec <= staleSeconds
        } else {
            pollingOK = startupGraceActive
        }

        let payload = HealthzPayload(
            status: (dbOK && pollingOK) ? "ok" : "degraded",
            db: dbOK ? "up" : "down",
            telegramPolling: pollingOK ? "up" : "down",
            pollLagSec: pollLagSec,
            startupGraceActive: startupGraceActive,
            lastPollOkAt: pollingSnapshot.lastSuccessfulPollAt.map(healthDateString),
            lastPollError: pollingSnapshot.lastErrorMessage,
            env: req.application.environment.name
        )

        let isHealthy = dbOK && pollingOK
        let res = Response(status: isHealthy ? .ok : .serviceUnavailable)
        try res.content.encode(payload, as: .json)
        return res
    }
}

private struct HealthzPayload: Content {
    let status: String
    let db: String
    let telegramPolling: String
    let pollLagSec: Int?
    let startupGraceActive: Bool
    let lastPollOkAt: String?
    let lastPollError: String?
    let env: String

    enum CodingKeys: String, CodingKey {
        case status
        case db
        case telegramPolling = "telegram_polling"
        case pollLagSec = "poll_lag_sec"
        case startupGraceActive = "startup_grace_active"
        case lastPollOkAt = "last_poll_ok_at"
        case lastPollError = "last_poll_error"
        case env
    }
}

private func healthEnvInt(name: String, defaultValue: Int) -> Int {
    guard let raw = Environment.get(name), let value = Int(raw), value > 0 else {
        return defaultValue
    }
    return value
}

private func healthDateString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

// MARK: - Feature routes stubs

extension Application {
    func kudosRoutes() throws {
        // Заглушка под будущие HTTP-роуты фичи “Kudos”.
        // Пример:
        // self.get("kudos") { req async throws -> [Kudos] in
        //     try await Kudos.query(on: req.db).all()
        // }
    }

    func exportRoutes() throws {
        // Здесь можно добавить HTTP-эндпоинт для скачивания CSV при необходимости.
    }
}
