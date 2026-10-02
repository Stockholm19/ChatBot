//
//  FormattingTests.swift
//  ChatBotTests
//
//  Тесты без базы данных: разбор callback'ов, времени, тексты напоминаний и итогов.
//

@testable import App
import XCTest

final class FormattingTests: XCTestCase {

    // MARK: - htmlEscaped / truncated

    func testHtmlEscapedEscapesTelegramSpecialCharacters() {
        XCTAssertEqual("<b>Том & Джерри</b>".htmlEscaped, "&lt;b&gt;Том &amp; Джерри&lt;/b&gt;")
    }

    func testTruncatedAddsEllipsisOnlyWhenNeeded() {
        XCTAssertEqual("спасибо".truncated(to: 10), "спасибо")
        XCTAssertEqual("спасибо".truncated(to: 3), "спа…")
    }

    // MARK: - parseReactionCallback

    func testParseReactionCallbackRejectsGarbage() {
        let id = UUID().uuidString
        XCTAssertNil(BotMenuController.parseReactionCallback("react:99:\(id)"), "Индекс вне списка реакций")
        XCTAssertNil(BotMenuController.parseReactionCallback("react:0:not-a-uuid"))
        XCTAssertNil(BotMenuController.parseReactionCallback("emp:pick:\(id)"))
        XCTAssertNil(BotMenuController.parseReactionCallback("react:0"))
    }

    // MARK: - ClockScheduler.TimeOfDay

    func testTimeOfDayParsing() {
        XCTAssertEqual(ClockScheduler.TimeOfDay("21:30")?.hour, 21)
        XCTAssertEqual(ClockScheduler.TimeOfDay(" 09:05 ")?.minute, 5)
        XCTAssertNil(ClockScheduler.TimeOfDay("24:00"))
        XCTAssertNil(ClockScheduler.TimeOfDay("12:60"))
        XCTAssertNil(ClockScheduler.TimeOfDay("полдень"))
    }

    func testTimeOfDayListSkipsInvalidValues() {
        let list = ClockScheduler.TimeOfDay.list("10:00, oops, 21:30")
        XCTAssertEqual(list.map(\.hour), [10, 21])
        XCTAssertTrue(ClockScheduler.TimeOfDay.list(nil).isEmpty)
    }

    // MARK: - RemindersService.composeMessage

    func testReminderSubstitutesNameWhenSingleCounterpart() {
        let text = RemindersService.composeMessage(from: ["{name} будет рад(а) 💌"], otherName: "Саша")
        XCTAssertTrue(text.hasPrefix("Саша будет рад(а) 💌"))
        XCTAssertTrue(text.contains(KeyboardBuilder.MainMenuButton.sayThanks))
    }

    func testReminderSkipsPlaceholderMessagesWithoutName() {
        let messages = ["{name} будет рад(а)", "Скажи спасибо 💛"]
        for _ in 0..<20 {
            let text = RemindersService.composeMessage(from: messages, otherName: nil)
            XCTAssertFalse(text.contains("{name}"))
            XCTAssertTrue(text.hasPrefix("Скажи спасибо 💛"))
        }
    }

    func testReminderFallsBackWhenOnlyPlaceholderMessages() {
        let text = RemindersService.composeMessage(from: ["{name}!"], otherName: nil)
        XCTAssertTrue(text.hasPrefix(RemindersService.fallbackMessage))
    }

    func testBundledReminderMessagesAreValidAndFriendly() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Reminders/messages.json")
        let messages = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))

        XCTAssertFalse(messages.isEmpty)
        XCTAssertTrue(messages.contains { !$0.contains(RemindersService.namePlaceholder) },
                      "Нужны тексты без {name} на случай, если участников больше двух")
        for message in messages {
            XCTAssertFalse(message.contains("коллег"), "Рабочие формулировки не должны остаться: \(message)")
            XCTAssertFalse(message.contains("@"), "Не упоминаем старый рабочий бот: \(message)")
        }
    }

    // MARK: - Weekly digest & stats

    func testWeeklyDigestForQuietWeek() {
        let text = WeeklyDigestService.format(.init(sent: 0, received: 0, highlight: nil))
        XCTAssertTrue(text.contains("спасибо не звучали"))
    }

    func testWeeklyDigestCounts() {
        let text = WeeklyDigestService.format(.init(sent: 3, received: 2, highlight: nil))
        XCTAssertTrue(text.contains("Ты сказал(а) спасибо: 3"))
        XCTAssertTrue(text.contains("Тебе сказали спасибо: 2"))
    }

    func testStatsFormatting() {
        let stats = KudosService.PersonalStats(sentTotal: 10, receivedTotal: 7, sentLastWeek: 2, receivedLastWeek: 1, reactionsOnSent: 5)
        let text = BotMenuController.formatStats(stats)
        XCTAssertTrue(text.contains("Отправлено: 10 (за неделю: 2)"))
        XCTAssertTrue(text.contains("Получено: 7 (за неделю: 1)"))
        XCTAssertTrue(text.contains("реакций на твои спасибо: 5"))
    }
}
