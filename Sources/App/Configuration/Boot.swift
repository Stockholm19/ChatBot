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
    // MARK: - Seed employees from Resources/SeedData/employees.csv (run once if empty)
    Task {
        do {
            try await app.autoMigrate()
            
            let count = try await Employee.query(on: app.db).count()
            if count == 0 {
                app.logger.info("Employees table empty. Seeding from CSV…")
                try await seedEmployees(app: app)
            } else {
                app.logger.info("Employees table has \(count) rows. Skipping seed.")
            }
        } catch {
            app.logger.critical("Migrate/Seed failed: \(error)")
        }
    }
    
    
    // Слушать на всех интерфейсах (чтобы было доступно извне контейнера)
    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080
}

private func seedEmployees(app: Application) async throws {
    let path = app.directory.resourcesDirectory + "SeedData/employees.csv"
    app.logger.info("Seed: reading \(path)")

    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let content = String(data: data, encoding: .utf8) else {
        app.logger.error("Seed: cannot read employees.csv at \(path)")
        return
    }

    let rows = content.split(separator: "\n").dropFirst()
    try await app.db.transaction { db in
        var inserted = 0
        for row in rows {
            let cols = row.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cols.count >= 3 else { continue }

            let fullName = cols[0]
            if fullName.isEmpty { continue }

            let active = ["да","yes","true","1"].contains(cols[1].lowercased())
            let tgId = Int64(cols[2])

            var e = Employee(fullName: String(fullName), position: nil, isActive: active)
            e.telegramId = tgId

            try await e.create(on: db)
            inserted += 1
        }
        app.logger.info("Seed: inserted \(inserted) employees")
    }
}
