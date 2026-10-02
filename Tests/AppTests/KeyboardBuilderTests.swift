//
//  KeyboardBuilderTests.swift
//  ChatBotTests
//
//  Набор тестов для KeyboardBuilder.
//

@testable import App
import XCTest
import Foundation

final class KeyboardBuilderTests: XCTestCase {

    // MARK: - mainMenu(isAdmin:)

    /// Обычный участник: «Сказать спасибо», лента + банка, статистика — без настроек
    func testMainMenuForRegularUser() throws {
        let keyboard = KeyboardBuilder.mainMenu(isAdmin: false)

        XCTAssertEqual(keyboard.keyboard.count, 3, "Для обычного участника ожидаем 3 строки")
        XCTAssertEqual(keyboard.keyboard[0].map(\.text), ["💌 Сказать спасибо"])
        XCTAssertEqual(keyboard.keyboard[1].map(\.text), ["📜 Наши спасибо", "🫙 Вспомнить"])
        XCTAssertEqual(keyboard.keyboard[2].map(\.text), ["📊 Статистика"])
    }

    /// Админ: дополнительно появляется строка «Настройки»
    func testMainMenuForAdmin() throws {
        let keyboard = KeyboardBuilder.mainMenu(isAdmin: true)

        XCTAssertEqual(keyboard.keyboard.count, 4, "Для админа ожидаем 4 строки")
        XCTAssertEqual(keyboard.keyboard[3].map(\.text), ["⚙️ Настройки"])
    }

    /// Тексты кнопок совпадают с константами, по которым идёт роутинг
    func testMainMenuUsesRoutingConstants() throws {
        let texts = KeyboardBuilder.mainMenu(isAdmin: true).keyboard.flatMap { $0.map(\.text) }
        XCTAssertEqual(texts, [
            KeyboardBuilder.MainMenuButton.sayThanks,
            KeyboardBuilder.MainMenuButton.feed,
            KeyboardBuilder.MainMenuButton.jar,
            KeyboardBuilder.MainMenuButton.stats,
            KeyboardBuilder.MainMenuButton.settings
        ])
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

    /// Получатель выбран автоматически — возвращаться к списку некуда, только «Отмена»
    func testReasonMenuWithoutBack() throws {
        let keyboard = KeyboardBuilder.reasonMenu(showBack: false)

        XCTAssertEqual(keyboard.keyboard.count, 1)
        XCTAssertEqual(keyboard.keyboard[0].map(\.text), ["Отмена"])
    }

    // MARK: - backToEmployeesList()

    /// Проверяем клавиатуру «Назад к списку»
    func testBackToEmployeesList() throws {
        let keyboard = KeyboardBuilder.backToEmployeesList()

        XCTAssertEqual(keyboard.keyboard.count, 1)
        XCTAssertEqual(keyboard.keyboard[0].map(\.text), ["← Назад к списку"])
    }

    // MARK: - statisticsMenu()

    /// Меню статистики — две выгрузки + «Назад» (сама статистика показывается при входе)
    func testStatisticsMenuLayout() throws {
        let keyboard = KeyboardBuilder.statisticsMenu()

        XCTAssertEqual(keyboard.keyboard.count, 3, "В меню статистики ожидаем 3 строки")
        XCTAssertEqual(keyboard.keyboard[0].map(\.text), ["📤 Выгрузить отправленные"])
        XCTAssertEqual(keyboard.keyboard[1].map(\.text), ["📥 Выгрузить полученные"])
        XCTAssertEqual(keyboard.keyboard[2].map(\.text), ["← Назад"])
    }

    // MARK: - adminMenu()

    func testAdminMenuUsesParticipantWording() throws {
        let keyboard = KeyboardBuilder.adminMenu()
        let allTexts = keyboard.keyboard.flatMap { $0.map(\.text) }
        XCTAssertTrue(allTexts.contains("👤 Добавить участника"))
        XCTAssertTrue(allTexts.contains("✏️ Изменить имя"))
        XCTAssertFalse(allTexts.contains { $0.contains("сотрудник") || $0.contains("ФИО") })
    }

    // MARK: - reactionsInline(kudosId:)

    func testReactionsInlineBuildsParsableCallbacks() throws {
        let kudosId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let keyboard = KeyboardBuilder.reactionsInline(kudosId: kudosId)

        XCTAssertEqual(keyboard.inline_keyboard.count, 1)
        XCTAssertEqual(keyboard.inline_keyboard[0].map(\.text), KeyboardBuilder.reactions)

        for (index, button) in keyboard.inline_keyboard[0].enumerated() {
            XCTAssertLessThanOrEqual(button.callback_data.utf8.count, 64, "Telegram ограничивает callback_data 64 байтами")
            let parsed = BotMenuController.parseReactionCallback(button.callback_data)
            XCTAssertEqual(parsed?.emoji, KeyboardBuilder.reactions[index])
            XCTAssertEqual(parsed?.kudosId, kudosId)
        }
    }

    func testEmployeesInlinePageBuildsCallbacks() throws {
        let id1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let id2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let keyboard = KeyboardBuilder.employeesInlinePage(
            options: [
                .init(id: id1, title: "Аня"),
                .init(id: id2, title: "Борис")
            ],
            hasPrev: true,
            hasNext: false,
            page: 1,
            callbackPrefix: "emp"
        )

        XCTAssertEqual(keyboard.inline_keyboard.count, 3)
        XCTAssertEqual(keyboard.inline_keyboard[0].map(\.text), ["Аня", "Борис"])
        XCTAssertEqual(
            keyboard.inline_keyboard[0].map(\.callback_data),
            ["emp:pick:\(id1.uuidString)", "emp:pick:\(id2.uuidString)"]
        )
        XCTAssertEqual(keyboard.inline_keyboard[1].map(\.callback_data), ["emp:page:0"])
        XCTAssertEqual(keyboard.inline_keyboard[2].map(\.callback_data), ["emp:back"])
    }
}
