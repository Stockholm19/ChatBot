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
    
        // Определил URL базы данных
        let databaseURL: String

        if let envURL = Environment.get("DATABASE_URL") {
            // Если явно задано DATABASE_URL — используем его во всех окружениях
            databaseURL = envURL
        } else if app.environment == .testing {
            // Дефолт для локального тестового окружения (порт 5433 из docker-compose.test.yml)
            databaseURL = "postgresql://postgres:postgres@localhost:5433/kudos_test?sslmode=disable"
        } else {
            // Дефолт для разработки/прода (порт 5432)
            databaseURL = "postgresql://postgres:postgres@localhost:5432/kudos?sslmode=disable"
        }

        try app.databases.use(.postgres(url: databaseURL), as: .psql)
        // --- Конец настройки базы данных ---

        // Регистрация миграций
        migrations(app)

        // Регистрация маршрутов
        try routes(app)

        // Автоматическое применение миграций и СИНХРОНИЗАЦИЯ
        // Запускаем ТОЛЬКО если это не тестирование
        if app.environment != .testing {
            Task {
                do {
                    try await app.autoMigrate()

                    let shouldImportCSV = Environment.get("EMPLOYEES_CSV_IMPORT_ON_BOOT") == "1"
                    if shouldImportCSV {
                        app.logger.info("Employees CSV import enabled (import-only).")
                        try await synchronizeEmployees(app: app)
                    } else {
                        app.logger.info("Employees CSV import disabled. Admin panel is source of truth.")
                    }
                } catch {
                    app.logger.critical("Migrate/Sync failed: \(error)")
                }
            }
    }
    
    
    // Настройки HTTP. Слушать на всех интерфейсах (чтобы было доступно извне контейнера)
    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080
    
    // Планировщики — отключаем в тестовом окружении
    if app.environment != .testing {
        RemindersScheduler.setup(app: app)
        PendingLinksScheduler.setup(app: app)
    }
}

/// Синхронизирует сотрудников из CSV-файла с базой данных.
private func synchronizeEmployees(app: Application) async throws {
    let path = app.directory.resourcesDirectory + "SeedData/employees.csv"
    app.logger.info("Sync: reading \(path)")

    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let content = String(data: data, encoding: .utf8) else {
        app.logger.error("Sync: cannot read employees.csv at \(path)")
        return
    }

    // 1. Парсим CSV сразу в неизменяемый словарь [FullName: Data], чтобы избежать проблем с concurrency.
    let csvRows = content.split(separator: "\n").dropFirst()
    let groupedCsvEmployees = Dictionary(
        grouping: csvRows.compactMap { row -> (String, Bool, Int64?)? in
            let cols = row.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cols.count >= 3 else { return nil }

            let fullName = String(cols[0])
            guard !fullName.isEmpty else { return nil }

            let isActive = ["да", "yes", "true", "1"].contains(cols[1].lowercased())
            let telegramId = Int64(cols[2])
            return (fullName, isActive, telegramId)
        },
        by: { $0.0 }
    )

    var csvEmployees: [String: (isActive: Bool, telegramId: Int64?)] = [:]

    for (name, group) in groupedCsvEmployees {
        if group.count == 1 {
            let g = group[0]
            csvEmployees[name] = (g.1, g.2)
            continue
        }

        let chosen = group.max { a, b in
            let aHasTg = a.2 != nil
            let bHasTg = b.2 != nil
            if aHasTg != bHasTg { return aHasTg == false }
            return false
        }

        if let chosen {
            csvEmployees[name] = (chosen.1, chosen.2)
            app.logger.warning("employees_csv_duplicate_full_name name=\"\(name)\" count=\(group.count)")
        }
    }
    
    let csvEmployeesSnapshot = csvEmployees
    try await app.db.transaction { db in
        // 2. Загружаем всех существующих сотрудников из БД в словарь для быстрого доступа
        let allDbEmployees = try await Employee.query(on: db).all()
        let groupedDbEmployees = Dictionary(grouping: allDbEmployees, by: { $0.fullName })
        var dbEmployeesDict: [String: Employee] = [:]

        for (name, group) in groupedDbEmployees {
            if group.count == 1, let only = group.first {
                dbEmployeesDict[name] = only
                continue
            }

            let chosen = group.max { a, b in
                let aHasTg = a.telegramId != nil
                let bHasTg = b.telegramId != nil
                if aHasTg != bHasTg { return aHasTg == false }

                let aDate = a.createdAt ?? .distantPast
                let bDate = b.createdAt ?? .distantPast
                return aDate < bDate
            }

            if let chosen {
                dbEmployeesDict[name] = chosen
                let ids = group.compactMap { try? $0.requireID().uuidString }.joined(separator: ",")
                let chosenId = (try? chosen.requireID().uuidString) ?? "unknown"
                app.logger.warning(
                    "employees_db_duplicate_full_name name=\"\(name)\" ids=[\(ids)] chosen=\(chosenId)"
                )
            }
        }
        
        var createdCount = 0
        var skippedExistingCount = 0

        // 3. CSV import-only: создаем только отсутствующих сотрудников. Ничего не обновляем и никого не деактивируем.
        for (fullName, csvData) in csvEmployeesSnapshot {
            if dbEmployeesDict[fullName] != nil {
                skippedExistingCount += 1
                continue
            }

            let newEmployee = Employee(
                fullName: fullName,
                position: nil,
                isActive: csvData.isActive
            )
            newEmployee.telegramId = csvData.telegramId
            try await newEmployee.create(on: db)
            createdCount += 1
        }
        
        app.logger.info("CSV import complete. Created: \(createdCount), Skipped(existing): \(skippedExistingCount).")
    }
}
