//
//  AppTests.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 25.11.2025.
//

@testable import App
import XCTVapor

final class AppTests: XCTestCase {
    
    func testDatabaseConnection() throws {
        // 1. Создаем приложение в режиме тестирования
        let app = Application(.testing)
        defer { app.shutdown() }
        
        // 2. Конфигурируем приложение (используется логика из Boot.configure)
        try configure(app)
        
        // 3. Проверяем, что autoMigrate не выбрасывает ошибок подключения
        XCTAssertNoThrow(try app.autoMigrate().wait())
    }
    
    func testHealthEndpoint() throws {
        // 1. Создаем приложение в режиме тестирования
        let app = Application(.testing)
        defer { app.shutdown() }

        // 2. Конфигурируем приложение
        try configure(app)

        // 3. Выполняем миграции (если есть)
        try app.autoMigrate().wait()

        // 4. Проверяем, что эндпоинт /health отвечает 200 OK
        try app.test(.GET, "health") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }
}
