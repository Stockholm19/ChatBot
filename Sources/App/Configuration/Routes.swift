//
//  Routes.swift
//  kudos-vapor
//
//  Created by Роман Пшеничников on 23.09.2025.
//

import Vapor
import Fluent
import SQLKit   //нужно для прямого SQL-запроса

public func routes(_ app: Application) throws {
    try app.kudosRoutes()
    try app.exportRoutes()

    // Простой healthcheck (для Docker/Load Balancer)
    app.get("health") { _ in "ok" }

    // Расширенный healthcheck для Uptime Kuma: проверка HTTP + БД
    //
    // Возвращает JSON вида:
    // {
    //   "status": "ok" | "degraded",
    //   "db": "up" | "down",
    //   "env": "<dev|prod|...>"
    // }
    //
    // Код ответа:
    //  - 200 OK, если БД “up”
    //  - 503 Service Unavailable, если БД “down” или SQL недоступен
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

        let payload: [String: String] = [
            "status": dbOK ? "ok" : "degraded",
            "db": dbOK ? "up" : "down",
            "env": req.application.environment.name
        ]

        let res = Response(status: dbOK ? .ok : .serviceUnavailable)
        try res.content.encode(payload, as: .json)
        return res
    }
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
