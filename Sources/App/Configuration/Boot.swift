//
//  Boot.swift
//  kudos-vapor
//
//  Created by Роман Пшеничников on 23.09.2025.
//

import Vapor
import Fluent
import FluentSQLiteDriver   // пока SQLite, но потом замени на Postgres

public func configure(_ app: Application) throws {
    // Настройка базы данных: файл хранится в /data (совпадает с docker-compose volume)
    app.databases.use(.sqlite(.file("/data/kudos.sqlite")), as: .sqlite)

    // Регистрация миграций
    migrations(app)

    // Регистрация маршрутов
    try routes(app)

    // Автоматическое применение миграций при старте (без падения в dev)
    Task { try? await app.autoMigrate() }
}
