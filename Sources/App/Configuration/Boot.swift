//
//  Boot.swift
//  kudos-vapor
//
//  Created by Роман Пшеничников on 23.09.2025.
//

import Vapor
import Fluent
import FluentPostgresDriver

public func configure(_ app: Application) throws {
    
    // PostgreSQL через DATABASE_URL
    let url = Environment.get("DATABASE_URL")
    ?? "postgresql://postgres:postgres@localhost:5432/kudos?sslmode=disable"
    try app.databases.use(.postgres(url: url), as: .psql)

    // Регистрация миграций
    migrations(app)

    // Регистрация маршрутов
    try routes(app)

    // Автоматическое применение миграций при старте (без падения в dev)
    Task { try? await app.autoMigrate() }
}
