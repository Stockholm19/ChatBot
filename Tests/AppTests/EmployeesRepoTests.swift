//
//  EmployeesRepoTests.swift
//  ChatBotTests
//
//  Набор тестов для работы с сотрудниками (Employee + FluentEmployeesRepo).
//

@testable import App
import XCTVapor
import Fluent

final class EmployeesRepoTests: XCTestCase {
    // MARK: - Общий экземпляр приложения для тестов
    private var app: Application!

    // MARK: - Создание приложения в режиме тестирования (async API)
    private func makeTestApp() async throws -> Application {
        let app = try await Application.make(.testing)
        try configure(app) // конфигурация приложения (Boot.configure)
        return app
    }

    // MARK: - setUp / tearDown

    override func setUp() async throws {
        try await super.setUp()

        // 1. Создаем приложение в режиме тестирования
        app = try await makeTestApp()

        // 2. Выполняем миграции (если есть)
        try await app.autoMigrate()

        // 3. Чистим таблицу сотрудников перед каждым тестом
        try await Employee.query(on: app.db).delete()
    }

    override func tearDown() async throws {
        // Аккуратно завершаем работу приложения
        if app != nil {
            try await app.asyncShutdown()
            app = nil
        }

        try await super.tearDown()
    }

    // MARK: - Вспомогательный хелпер для создания сотрудника

    /// Удобный метод, чтобы быстро создавать сотрудников в тестах
    @discardableResult
    private func makeEmployee(
        fullName: String,
        position: String? = nil,
        isActive: Bool = true,
        telegramId: Int64? = nil
    ) async throws -> Employee {
        let employee = Employee(fullName: fullName,
                                position: position,
                                isActive: isActive)
        employee.telegramId = telegramId
        try await employee.create(on: app.db)
        return employee
    }

    // MARK: - Тест 1. Пагинация: page(_:per:)

    /// Проверяем, что:
    /// - метод page(_:per:) возвращает только активных сотрудников
    /// - сортировка по fullName по возрастанию
    /// - total считает только активных
    func testPageReturnsOnlyActiveEmployeesSortedByName() async throws {
        let repo = FluentEmployeesRepo(db: app.db)

        // given: 3 сотрудника, из них двое активные
        let _ = try await makeEmployee(fullName: "Charlie", isActive: true)
        let _ = try await makeEmployee(fullName: "Alice", isActive: true)
        let _ = try await makeEmployee(fullName: "Bob", isActive: false)

        // when: запрашиваем первую страницу по 10 записей
        let result = try await repo.page(1, per: 10)

        // then: total = 2 (только активные)
        XCTAssertEqual(result.total, 2)

        // then: вернулись 2 записи и они отсортированы по fullName
        XCTAssertEqual(result.items.count, 2)
        let names = result.items.map(\.fullName)
        XCTAssertEqual(names, ["Alice", "Charlie"])
    }

    // MARK: - Тест 2. Поиск: search(_:page:per:)

    /// Проверяем, что метод search(_:,page:per:) ищет по имени
    /// и возвращает только активных сотрудников, подходящих под запрос.
    func testSearchFindsEmployeesByName() async throws {
        let repo = FluentEmployeesRepo(db: app.db)

        // given
        let _ = try await makeEmployee(fullName: "Анна Смирнова", isActive: true)
        let _ = try await makeEmployee(fullName: "Иван Иванов", isActive: true)
        let _ = try await makeEmployee(fullName: "Техническая поддержка", isActive: true)
        let _ = try await makeEmployee(fullName: "Неактивный Анна", isActive: false)

        // when: ищем по подстроке "Анна"
        let result = try await repo.search("Анна", page: 1, per: 10)

        // then: должны найти только активную "Анна Смирнова"
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.fullName, "Анна Смирнова")
    }

    // MARK: - Тест 3. Получение по ID: get(_:)

    /// Проверяем, что get(_:) возвращает сотрудника по его UUID
    func testGetReturnsEmployeeById() async throws {
        let repo = FluentEmployeesRepo(db: app.db)

        // given
        let created = try await makeEmployee(fullName: "User By ID")
        guard let id = created.id else {
            XCTFail("У созданного сотрудника должен быть id")
            return
        }

        // when
        let found = try await repo.get(id)

        // then
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, id)
        XCTAssertEqual(found?.fullName, "User By ID")
    }

    // MARK: - Тест 4. Поиск по Telegram ID: findByTelegramId(_:)

    /// Проверяем, что findByTelegramId(_:) находит сотрудника по telegram_id
    func testFindByTelegramIdReturnsEmployee() async throws {
        let repo = FluentEmployeesRepo(db: app.db)

        // given
        let tgId: Int64 = 424242
        let created = try await makeEmployee(fullName: "Telegram User",
                                             isActive: true,
                                             telegramId: tgId)

        // when
        let found = try await repo.findByTelegramId(tgId)

        // then
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, created.id)
        XCTAssertEqual(found?.telegramId, tgId)
        XCTAssertEqual(found?.fullName, "Telegram User")
    }

    /// Проверяем, что при несуществующем telegram_id возвращается nil
    func testFindByTelegramIdReturnsNilForUnknownId() async throws {
        let repo = FluentEmployeesRepo(db: app.db)

        // when
        let found = try await repo.findByTelegramId(999_999)

        // then
        XCTAssertNil(found)
    }
    
    // MARK: - Тест 5. Пагинация на пустой базе

    /// Проверяем, что page(_:per:) на пустой базе возвращает пустой результат
    func testPageOnEmptyDatabaseReturnsEmptyResult() async throws {
        let repo = FluentEmployeesRepo(db: app.db)

        // given: в setUp база очищена, сотрудников нет

        // when
        let result = try await repo.page(1, per: 10)

        // then
        XCTAssertEqual(result.total, 0, "total должен быть 0 на пустой базе")
        XCTAssertTrue(result.items.isEmpty, "items должен быть пустым на пустой базе")
    }

    // MARK: - Тест 6. Поиск на пустой базе

    /// Проверяем, что search(_:page:per:) на пустой базе возвращает пустой результат
    func testSearchOnEmptyDatabaseReturnsEmptyResult() async throws {
        let repo = FluentEmployeesRepo(db: app.db)

        // given: база пуста

        // when
        let result = try await repo.search("Анна", page: 1, per: 10)

        // then
        XCTAssertEqual(result.total, 0, "total должен быть 0 при поиске по пустой базе")
        XCTAssertTrue(result.items.isEmpty, "items должен быть пустым при поиске по пустой базе")
    }

    // MARK: - Тест 7. Пагинация по страницам

    /// Проверяем, что:
    /// - page(_:per:) корректно разбивает сотрудников по страницам
    /// - сортировка по fullName сохраняется на всех страницах
    func testPageSplitsEmployeesAcrossPages() async throws {
        let repo = FluentEmployeesRepo(db: app.db)

        // given: 5 активных сотрудников с именами, чтобы проверить сортировку
        _ = try await makeEmployee(fullName: "Alice", isActive: true)
        _ = try await makeEmployee(fullName: "Bob", isActive: true)
        _ = try await makeEmployee(fullName: "Charlie", isActive: true)
        _ = try await makeEmployee(fullName: "Dave", isActive: true)
        _ = try await makeEmployee(fullName: "Eve", isActive: true)

        // when: первая страница по 2 записи
        let page1 = try await repo.page(1, per: 2)
        // вторая страница
        let page2 = try await repo.page(2, per: 2)
        // третья страница
        let page3 = try await repo.page(3, per: 2)

        // then: total всегда 5 (всего активных сотрудников)
        XCTAssertEqual(page1.total, 5)
        XCTAssertEqual(page2.total, 5)
        XCTAssertEqual(page3.total, 5)

        // Проверяем, что сотрудники идут по алфавиту и разбиваются по страницам:
        XCTAssertEqual(page1.items.map(\.fullName), ["Alice", "Bob"])
        XCTAssertEqual(page2.items.map(\.fullName), ["Charlie", "Dave"])
        XCTAssertEqual(page3.items.map(\.fullName), ["Eve"])
    }
}
