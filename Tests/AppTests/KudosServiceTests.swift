//
//  KudosServiceTests.swift
//  ChatBotTests
//
//  Интеграционные тесты KudosService: статистика, лента, банка, реакции, итоги недели.
//

@testable import App
import XCTVapor
import Fluent

final class KudosServiceTests: XCTestCase {

    private var app: Application!
    private var me: Employee!
    private var partner: Employee!

    override func setUp() async throws {
        try await super.setUp()
        app = try await Application.make(.testing)
        try configure(app)
        try await app.autoMigrate()

        try await Kudos.query(on: app.db).delete()
        try await PendingLink.query(on: app.db).delete()
        try await Employee.query(on: app.db).delete()

        me = try await makeParticipant(name: "Рома", telegramId: 1001)
        partner = try await makeParticipant(name: "Саша", telegramId: 1002)
    }

    override func tearDown() async throws {
        if app != nil {
            try await app.asyncShutdown()
            app = nil
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeParticipant(name: String, telegramId: Int64?, isActive: Bool = true) async throws -> Employee {
        let employee = Employee(fullName: name, isActive: isActive)
        employee.telegramId = telegramId
        try await employee.save(on: app.db)
        return employee
    }

    @discardableResult
    private func thanks(from sender: Employee, to recipient: Employee, _ reason: String, at date: Date = Date(), reaction: String? = nil) async throws -> Kudos {
        let kudos = Kudos(
            ts: date,
            fromUserId: sender.telegramId ?? 0,
            fromUsername: "@\(sender.fullName)",
            fromName: sender.fullName,
            toUsername: "@unknown",
            reason: reason,
            employeeId: try recipient.requireID(),
            fromEmployeeId: try sender.requireID()
        )
        kudos.reaction = reaction
        try await kudos.save(on: app.db)
        return kudos
    }

    private var service: KudosService { KudosService(db: app.db) }
    private let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 3600)

    // MARK: - Participants

    func testActiveLinkedExcludesInactiveAndUnlinked() async throws {
        try await makeParticipant(name: "Без Telegram", telegramId: nil)
        try await makeParticipant(name: "Отключённый", telegramId: 1003, isActive: false)

        let names = try await FluentEmployeesRepo(db: app.db).activeLinked().map(\.fullName)
        XCTAssertEqual(names, ["Рома", "Саша"])
    }

    // MARK: - Stats

    func testStatsCountsTotalsWeekAndReactions() async throws {
        try await thanks(from: me, to: partner, "за ужин", reaction: "❤️")
        try await thanks(from: me, to: partner, "за прогулку", at: tenDaysAgo)
        try await thanks(from: partner, to: me, "за чай")

        let stats = try await service.stats(for: try me.requireID())
        XCTAssertEqual(stats, KudosService.PersonalStats(
            sentTotal: 2,
            receivedTotal: 1,
            sentLastWeek: 1,
            receivedLastWeek: 1,
            reactionsOnSent: 1
        ))
    }

    // MARK: - Feed

    func testRecentReturnsNewestFirstOnlyForParticipant() async throws {
        let stranger = try await makeParticipant(name: "Гость", telegramId: 1004)
        try await thanks(from: me, to: partner, "старое", at: tenDaysAgo)
        try await thanks(from: partner, to: me, "новое")
        try await thanks(from: stranger, to: partner, "чужое")

        let items = try await service.recent(involving: try me.requireID(), limit: 10)
        XCTAssertEqual(items.map(\.reason), ["новое", "старое"])
    }

    func testFeedItemShowsDirectionReactionAndEscapesText() async throws {
        try await thanks(from: me, to: partner, "за <торт> & кофе", reaction: "🥹")
        try await thanks(from: partner, to: me, "за поддержку")

        let meID = try me.requireID()
        let items = try await service.recent(involving: meID, limit: 10)
        let lines = items.map { BotMenuController.formatFeedItem($0, viewerId: meID) }

        XCTAssertTrue(lines.contains { $0.contains("Саша → тебе") && $0.contains("«за поддержку»") })
        XCTAssertTrue(lines.contains { $0.contains("Ты → Саша 🥹") && $0.contains("за &lt;торт&gt; &amp; кофе") })
    }

    // MARK: - Jar

    func testRandomReceivedIsNilWhenJarIsEmpty() async throws {
        try await thanks(from: me, to: partner, "только отправленное")
        let result = try await service.randomReceived(by: try me.requireID())
        XCTAssertNil(result)
    }

    func testRandomReceivedReturnsOnlyReceivedThanks() async throws {
        try await thanks(from: partner, to: me, "раз")
        try await thanks(from: partner, to: me, "два")
        try await thanks(from: me, to: partner, "моё")

        for _ in 0..<10 {
            let kudos = try await service.randomReceived(by: try me.requireID())
            XCTAssertNotNil(kudos)
            XCTAssertTrue(["раз", "два"].contains(kudos?.reason ?? ""))
            XCTAssertEqual(kudos?.senderDisplayName, "Саша", "Отправитель должен быть подгружен")
        }
    }

    // MARK: - Reactions

    func testOnlyRecipientCanReactAndOnlyOnce() async throws {
        let kudos = try await thanks(from: me, to: partner, "за ужин")
        let kudosId = try kudos.requireID()

        guard case .notRecipient = try await service.react(kudosId: kudosId, byTelegramId: 1001, reaction: "❤️") else {
            return XCTFail("Отправитель не может реагировать на своё спасибо")
        }

        guard case .reacted(let reacted) = try await service.react(kudosId: kudosId, byTelegramId: 1002, reaction: "🤗") else {
            return XCTFail("Получатель должен суметь отреагировать")
        }
        XCTAssertEqual(reacted.reaction, "🤗")
        XCTAssertEqual(reacted.fromEmployee?.telegramId, 1001, "Нужен Telegram отправителя для ответа")

        guard case .alreadyReacted(let existing) = try await service.react(kudosId: kudosId, byTelegramId: 1002, reaction: "❤️") else {
            return XCTFail("Повторная реакция не должна перезаписывать первую")
        }
        XCTAssertEqual(existing, "🤗")

        guard case .notFound = try await service.react(kudosId: UUID(), byTelegramId: 1002, reaction: "❤️") else {
            return XCTFail("Несуществующее спасибо")
        }
    }

    // MARK: - Reminders & digest

    func testHasSentToday() async throws {
        let meID = try me.requireID()
        try await thanks(from: me, to: partner, "вчерашнее", at: tenDaysAgo)
        let before = try await service.hasSentToday(employeeId: meID)
        XCTAssertFalse(before)

        try await thanks(from: me, to: partner, "сегодняшнее")
        let after = try await service.hasSentToday(employeeId: meID)
        XCTAssertTrue(after)
    }

    func testWeeklySummaryIgnoresOlderThanWeek() async throws {
        try await thanks(from: me, to: partner, "давно", at: tenDaysAgo)
        try await thanks(from: partner, to: me, "давнее полученное", at: tenDaysAgo)
        try await thanks(from: me, to: partner, "недавно")
        try await thanks(from: partner, to: me, "свежее полученное")

        let summary = try await service.weeklySummary(for: try me.requireID())
        XCTAssertEqual(summary.sent, 1)
        XCTAssertEqual(summary.received, 1)
        XCTAssertEqual(summary.highlight?.reason, "свежее полученное")

        let text = WeeklyDigestService.format(summary)
        XCTAssertTrue(text.contains("от Саша"))
        XCTAssertTrue(text.contains("«свежее полученное»"))
    }
}
