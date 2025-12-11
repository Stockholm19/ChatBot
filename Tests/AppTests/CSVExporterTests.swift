//
//  CSVExporterTests.swift
//  ChatBotTests
//
//  Тесты для CSVExporter.exportKudos(db:to:)
//

@testable import App
import XCTVapor
import Fluent
import Foundation

final class CSVExporterTests: XCTestCase {

    private var app: Application!

    /// Создает приложение в режиме тестирования (async API)
    private func makeTestApp() async throws -> Application {
        let app = try await Application.make(.testing)
        try configure(app) // конфигурация приложения (Boot.configure)
        return app
    }
    
    override func setUp() async throws {
        try await super.setUp()

        // 1. Создаем приложение в режиме тестирования
        app = try await makeTestApp()

        // 2. Выполняем миграции (если есть)
        try await app.autoMigrate()

        // 3. Чистим таблицу благодарностей перед каждым тестом
        try await Kudos.query(on: app.db).delete()
    }

    override func tearDown() async throws {
        // Аккуратно завершаем работу приложения
        if app != nil {
            try await app.asyncShutdown()
            app = nil
        }

        try await super.tearDown()
    }

    /// Проверяем, что экспорт:
    /// - создает файл,
    /// - добавляет BOM,
    /// - пишет header + строки данных,
    /// - использует `;` как разделитель,
    /// - содержит наши тексты благодарностей.
    func testExportKudosCreatesCsvWithAllRecords() async throws {
        let now = Date()

        // Создаем несколько записей Kudos
        let kudos1 = Kudos()
        kudos1.ts = now.addingTimeInterval(-60)
        kudos1.fromUserId = 1001
        kudos1.fromUsername = "alice"
        kudos1.fromName = "Alice Doe"
        kudos1.toUsername = "bob"
        kudos1.reason = "Спасибо за помощь с релизом приложения"
        try await kudos1.save(on: app.db)

        let kudos2 = Kudos()
        kudos2.ts = now
        kudos2.fromUserId = 1002
        kudos2.fromUsername = "charlie"
        kudos2.fromName = "Charlie Doe"
        kudos2.toUsername = "dave"
        kudos2.reason = "Спасибо за консультацию по базе данных"
        try await kudos2.save(on: app.db)

        // Путь до временного файла
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kudos-export-test.csv")

        // На всякий случай удаляем, если вдруг остался от прошлых запусков
        try? FileManager.default.removeItem(at: url)

        // when: запускаем экспорт
        try await CSVExporter.exportKudos(db: app.db, to: url.path)

        // then: файл создан
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "CSV-файл должен быть создан по заданному пути"
        )

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(
            data.count,
            3,
            "CSV-файл должен содержать хотя бы BOM и данные"
        )

        // 1. Проверяем BOM по байтам EF BB BF
        let bom = Array(data.prefix(3))
        XCTAssertEqual(
            bom,
            [0xEF, 0xBB, 0xBF],
            "CSV должен начинаться с UTF-8 BOM (EF BB BF) для корректного открытия в Excel"
        )

        // Убираем BOM, дальше работаем только с самим CSV
        guard let csv = String(data: data.dropFirst(3), encoding: .utf8) else {
            XCTFail("Не удалось декодировать CSV после BOM как UTF-8")
            return
        }

        // Разбиваем на строки, убираем пустые (последний \n)
        let lines = csv
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Должен быть header + 2 строки данных
        XCTAssertEqual(
            lines.count,
            1 + 2,
            "В CSV должен быть один заголовок и две строки данных (по количеству сохраненных Kudos)"
        )

        // 2. Проверяем, что в заголовке 5 колонок и используется `;`
        let headerColumns = lines[0].split(separator: ";")
        XCTAssertEqual(
            headerColumns.count,
            5,
            "Ожидаем 5 колонок в заголовке (дата, логин отправителя, отправитель, получатель, текст)"
        )

        // 3. Проверяем, что данные реально попали в CSV
        let csvText = csv

        XCTAssertTrue(
            csvText.contains("alice"),
            "CSV должен содержать логин отправителя alice"
        )
        XCTAssertTrue(
            csvText.contains("charlie"),
            "CSV должен содержать логин отправителя charlie"
        )
        XCTAssertTrue(
            csvText.contains("Спасибо за помощь с релизом приложения"),
            "CSV должен содержать текст первой благодарности"
        )
        XCTAssertTrue(
            csvText.contains("Спасибо за консультацию по базе данных"),
            "CSV должен содержать текст второй благодарности"
        )
    }

    /// Отдельный маленький тест на использование `;` как разделителя
    func testExportKudosUsesSemicolonDelimiter() async throws {
        let kudos = Kudos()
        kudos.ts = Date()
        kudos.fromUserId = 2001
        kudos.fromUsername = "eve"
        kudos.fromName = "Eve Doe"
        kudos.toUsername = "frank"
        kudos.reason = "Тестовая благодарность без точек с запятыми"
        try await kudos.save(on: app.db)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kudos-export-delimiter.csv")

        try? FileManager.default.removeItem(at: url)

        try await CSVExporter.exportKudos(db: app.db, to: url.path)

        let data = try Data(contentsOf: url)
        let csv: String
        if data.prefix(3) == Data([0xEF, 0xBB, 0xBF]) {
            // Файл с BOM — пропускаем первые 3 байта
            csv = String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        } else {
            // Без BOM — декодируем как есть
            csv = String(data: data, encoding: .utf8) ?? ""
        }

        let lines = csv
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        XCTAssertGreaterThan(lines.count, 1, "Должна быть хотя бы одна строка данных")

        // Берем первую строку данных (после хедера)
        let dataColumns = lines[1].split(separator: ";")
        XCTAssertEqual(
            dataColumns.count,
            5,
            "Строка данных должна разбиваться по `;` на 5 колонок"
        )
    }

    /// Проверяем, что при передаче кастомного массива `rows`
    /// экспортирует только указанные записи, а не все Kudos в базе.
    func testExportKudosWithCustomRowsExportsOnlyGivenRecords() async throws {
        let now = Date()

        // В базе создаём три записи
        let kudos1 = Kudos()
        kudos1.ts = now.addingTimeInterval(-120)
        kudos1.fromUserId = 3001
        kudos1.fromUsername = "user1"
        kudos1.fromName = "User One"
        kudos1.toUsername = "target"
        kudos1.reason = "Первая благодарность"
        try await kudos1.save(on: app.db)

        let kudos2 = Kudos()
        kudos2.ts = now.addingTimeInterval(-60)
        kudos2.fromUserId = 3002
        kudos2.fromUsername = "user2"
        kudos2.fromName = "User Two"
        kudos2.toUsername = "target"
        kudos2.reason = "Вторая благодарность"
        try await kudos2.save(on: app.db)

        let kudos3 = Kudos()
        kudos3.ts = now
        kudos3.fromUserId = 3003
        kudos3.fromUsername = "user3"
        kudos3.fromName = "User Three"
        kudos3.toUsername = "target"
        kudos3.reason = "Третья благодарность"
        try await kudos3.save(on: app.db)

        // Но в экспорт передаём только kudos2
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kudos-export-custom-rows.csv")

        // Удаляем старый файл, если был
        try? FileManager.default.removeItem(at: url)

        try await CSVExporter.exportKudos(db: app.db, rows: [kudos2], to: url.path)

        let data = try Data(contentsOf: url)
        let csv: String
        if data.prefix(3) == Data([0xEF, 0xBB, 0xBF]) {
            // С BOM
            csv = String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        } else {
            // Без BOM
            csv = String(data: data, encoding: .utf8) ?? ""
        }

        let lines = csv
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // header + 1 строка данных
        XCTAssertEqual(
            lines.count,
            2,
            "Ожидаем один заголовок и одну строку данных при экспорте только одного Kudos"
        )

        let csvText = csv
        XCTAssertTrue(
            csvText.contains("Вторая благодарность"),
            "CSV должен содержать только вторую благодарность"
        )
        XCTAssertFalse(
            csvText.contains("Первая благодарность"),
            "CSV не должен содержать первую благодарность"
        )
        XCTAssertFalse(
            csvText.contains("Третья благодарность"),
            "CSV не должен содержать третью благодарность"
        )
    }
}
