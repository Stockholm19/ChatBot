//
//  AppTests.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 25.11.2025.
//

@testable import App
import XCTVapor

final class AppTests: XCTestCase {
    // Общий экземпляр приложения для тестов
    private var app: Application!

    /// Создает приложение в режиме тестирования (async API)
    private func makeTestApp() async throws -> Application {
        let app = try await Application.make(.testing)
        try configure(app) // конфигурация приложения (Boot.configure)
        return app
    }

    override func setUp() async throws {
        try await super.setUp()

        // 1. Создаем приложение в режиме тестирования (async API)
        app = try await makeTestApp()

        // 2. Выполняем миграции (если есть)
        try await app.autoMigrate()
    }

    override func tearDown() async throws {
        // Аккуратно завершаем работу приложения
        if app != nil {
            try await app.asyncShutdown()
            app = nil
        }

        try await super.tearDown()
    }

    func testDatabaseConnection() async throws {
        // 1. Проверяем, что приложение успешно создано и миграции прошли без ошибок в setUp()
        XCTAssertNotNil(app)

        // 2. Дополнительно пробуем еще раз выполнить миграции,
        //    чтобы убедиться, что подключение к БД работает
        try await app.autoMigrate()
    }

    func testHealthEndpoint() async throws {
        // 1. Проверяем, что эндпоинт /health отвечает 200 OK
        try await app.test(.GET, "health") { res async in
            XCTAssertEqual(res.status, .ok)
        }
    }
}
