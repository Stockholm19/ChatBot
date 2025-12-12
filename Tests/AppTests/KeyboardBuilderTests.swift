//
//  KeyboardBuilderTests.swift
//  ChatBotTests
//
//  Набор тестов для KeyboardBuilder.
//

@testable import App
import XCTest

final class KeyboardBuilderTests: XCTestCase {

    // MARK: - mainMenu()

    /// Проверяем, что главное меню состоит из одной кнопки «Передать спасибо»
    func testMainMenuLayout() throws {
        let keyboard = KeyboardBuilder.mainMenu()

        XCTAssertEqual(keyboard.keyboard.count, 1, "Ожидаем одну строку в главном меню")
        XCTAssertEqual(keyboard.keyboard[0].count, 1, "Ожидаем одну кнопку в строке")
        XCTAssertEqual(keyboard.keyboard[0][0].text, "Передать спасибо")
    }

    // MARK: - thanksMenu(isAdmin:)

    /// Пользователь НЕ админ — без кнопки «Админка»
    func testThanksMenuForRegularUser() throws {
        let keyboard = KeyboardBuilder.thanksMenu(isAdmin: false)

        // Строки меню
        // 0: «Сказать «спасибо»»
        // 1: «📊 Статистика»
        // 2: «← Назад»
        XCTAssertEqual(keyboard.keyboard.count, 3, "Для обычного пользователя должно быть 3 строки")

        let row0 = keyboard.keyboard[0].map(\.text)
        let row1 = keyboard.keyboard[1].map(\.text)
        let row2 = keyboard.keyboard[2].map(\.text)

        XCTAssertEqual(row0, ["Сказать «спасибо»"])
        XCTAssertEqual(row1, ["Статистика"])
        XCTAssertEqual(row2, ["← Назад"])
    }

    /// Пользователь админ — появляется дополнительная кнопка «Админка»
    func testThanksMenuForAdmin() throws {
        let keyboard = KeyboardBuilder.thanksMenu(isAdmin: true)

        // Строки меню
        // 0: «Сказать «спасибо»»
        // 1: «Статистика»
        // 2: «Админка»
        // 3: «← Назад»
        XCTAssertEqual(keyboard.keyboard.count, 4, "Для админа должно быть 4 строки")

        let row0 = keyboard.keyboard[0].map(\.text)
        let row1 = keyboard.keyboard[1].map(\.text)
        let row2 = keyboard.keyboard[2].map(\.text)
        let row3 = keyboard.keyboard[3].map(\.text)

        XCTAssertEqual(row0, ["Сказать «спасибо»"])
        XCTAssertEqual(row1, ["Статистика"])
        XCTAssertEqual(row2, ["Админка"])
        XCTAssertEqual(row3, ["← Назад"])
    }

    // MARK: - employeesPage(names:hasPrev:hasNext:)

    /// Постраничный список: имена по 2 в строке + навигация и «Назад»
    func testEmployeesPageWithNavAndBack() throws {
        let names = ["Аня", "Борис", "Вася"]
        let keyboard = KeyboardBuilder.employeesPage(names: names,
                                                     hasPrev: true,
                                                     hasNext: false)

        // Ждем строки:
        // 0: «Аня» «Борис»
        // 1: «Вася»
        // 2: «⭠»
        // 3: «← Назад»
        XCTAssertEqual(keyboard.keyboard.count, 4)

        XCTAssertEqual(keyboard.keyboard[0].map(\.text), ["Аня", "Борис"])
        XCTAssertEqual(keyboard.keyboard[1].map(\.text), ["Вася"])
        XCTAssertEqual(keyboard.keyboard[2].map(\.text), ["<"])
        XCTAssertEqual(keyboard.keyboard[3].map(\.text), ["← Назад"])
    }

    /// Если нет hasPrev, но есть hasNext — навигационная строка только с « ⭢ »
    func testEmployeesPageNextOnly() throws {
        let names = ["Аня", "Борис"]
        let keyboard = KeyboardBuilder.employeesPage(names: names,
                                                     hasPrev: false,
                                                     hasNext: true)

        // 0: «Аня» «Борис»
        // 1: «⭢»
        // 2: «← Назад»
        XCTAssertEqual(keyboard.keyboard.count, 3)
        XCTAssertEqual(keyboard.keyboard[0].map(\.text), ["Аня", "Борис"])
        XCTAssertEqual(keyboard.keyboard[1].map(\.text), [">"])
        XCTAssertEqual(keyboard.keyboard[2].map(\.text), ["← Назад"])
    }

    // MARK: - chooseRecipientMenu()

    /// Меню выбора получателя — только «Назад»
    func testChooseRecipientMenu() throws {
        let keyboard = KeyboardBuilder.chooseRecipientMenu()

        XCTAssertEqual(keyboard.keyboard.count, 1)
        XCTAssertEqual(keyboard.keyboard[0].map(\.text), ["← Назад"])
    }

    // MARK: - reasonMenu()

    /// Меню ввода причины — «← Назад» + «Отмена» в одной строке
    func testReasonMenu() throws {
        let keyboard = KeyboardBuilder.reasonMenu()

        XCTAssertEqual(keyboard.keyboard.count, 1)
        XCTAssertEqual(keyboard.keyboard[0].map(\.text), ["← Назад", "Отмена"])
    }

    // MARK: - backToEmployeesList()

    /// Проверяем клавиатуру «Назад к списку»
    func testBackToEmployeesList() throws {
        let keyboard = KeyboardBuilder.backToEmployeesList()

        XCTAssertEqual(keyboard.keyboard.count, 1)
        XCTAssertEqual(keyboard.keyboard[0].map(\.text), ["← Назад к списку"])
    }

    // MARK: - statisticsMenu()

    /// Меню статистики — три действия + «Назад»
    func testStatisticsMenuLayout() throws {
        let keyboard = KeyboardBuilder.statisticsMenu()

        XCTAssertEqual(keyboard.keyboard.count, 4, "В меню статистики ожидаем 4 строки")

        let row0 = keyboard.keyboard[0].map(\.text)
        let row1 = keyboard.keyboard[1].map(\.text)
        let row2 = keyboard.keyboard[2].map(\.text)
        let row3 = keyboard.keyboard[3].map(\.text)

        XCTAssertEqual(row0, ["Моя статистика"])
        XCTAssertEqual(row1, ["Экспорт переданных"])
        XCTAssertEqual(row2, ["Экспорт полученных"])
        XCTAssertEqual(row3, ["← Назад"])
    }
}
