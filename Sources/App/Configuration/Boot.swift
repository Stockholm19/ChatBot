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

    // Автоматическое применение миграций и СИНХРОНИЗАЦИЯ сотрудников при старте
    Task {
        do {
            try await app.autoMigrate()
            app.logger.info("Starting employees synchronization from CSV...")
            try await synchronizeEmployees(app: app)
        } catch {
            app.logger.critical("Migrate/Sync failed: \(error)")
        }
    }
    
    
    // Настройки HTTP. Слушать на всех интерфейсах (чтобы было доступно извне контейнера)
    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080
    
    // Планировщик напоминаний
    RemindersScheduler.setup(app: app)
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
    let csvEmployees = Dictionary(uniqueKeysWithValues: csvRows.compactMap { row -> (String, (isActive: Bool, telegramId: Int64?))? in
        let cols = row.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cols.count >= 3 else { return nil }

        let fullName = String(cols[0])
        guard !fullName.isEmpty else { return nil }

        let isActive = ["да", "yes", "true", "1"].contains(cols[1].lowercased())
        let telegramId = Int64(cols[2])

        return (fullName, (isActive: isActive, telegramId: telegramId))
    })

    try await app.db.transaction { db in
        // 2. Загружаем всех существующих сотрудников из БД в словарь для быстрого доступа
        let allDbEmployees = try await Employee.query(on: db).all()
        var dbEmployeesDict = Dictionary(uniqueKeysWithValues: allDbEmployees.map { ($0.fullName, $0) })
        
        var createdCount = 0
        var updatedCount = 0
        var deactivatedCount = 0

        // 3. Проходимся по сотрудникам из CSV
        for (fullName, csvData) in csvEmployees {
            if let existingEmployee = dbEmployeesDict[fullName] {
                // СЦЕНАРИЙ: ОБНОВЛЕНИЕ. Сотрудник найден в базе.
                var needsUpdate = false
                if existingEmployee.isActive != csvData.isActive {
                    existingEmployee.isActive = csvData.isActive
                    needsUpdate = true
                }
                if existingEmployee.telegramId != csvData.telegramId {
                    existingEmployee.telegramId = csvData.telegramId
                    needsUpdate = true
                }

                if needsUpdate {
                    try await existingEmployee.update(on: db)
                    updatedCount += 1
                }
                
                // Удаляем из словаря, чтобы пометить его как "обработанный"
                dbEmployeesDict.removeValue(forKey: fullName)
                
            } else {
                // СЦЕНАРИЙ: ДОБАВЛЕНИЕ. Сотрудника нет в базе.
                let newEmployee = Employee(
                    fullName: fullName,
                    position: nil,
                    isActive: csvData.isActive
                )
                newEmployee.telegramId = csvData.telegramId
                try await newEmployee.create(on: db)
                createdCount += 1
            }
        }

        // 4. СЦЕНАРИЙ: ДЕАКТИВАЦИЯ.
        // Все, кто остался в `dbEmployeesDict`, есть в базе, но отсутствуют в CSV.
        for (_, oldEmployee) in dbEmployeesDict {
            if oldEmployee.isActive { // Деактивируем только активных
                oldEmployee.isActive = false
                try await oldEmployee.update(on: db)
                deactivatedCount += 1
            }
        }
        
        app.logger.info("Synchronization complete. Created: \(createdCount), Updated: \(updatedCount), Deactivated: \(deactivatedCount).")
    }
}
