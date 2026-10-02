//
//  KudosService.swift
//  ChatBot
//
//  Бизнес-логика вокруг благодарностей: статистика, лента, «банка»,
//  итоги недели и реакции получателя.
//

import Foundation
import Fluent

struct KudosService {
    let db: Database

    // MARK: - Statistics

    struct PersonalStats: Equatable {
        let sentTotal: Int
        let receivedTotal: Int
        let sentLastWeek: Int
        let receivedLastWeek: Int
        /// Сколько отправленных спасибо получили реакцию в ответ
        let reactionsOnSent: Int
    }

    func stats(for employeeId: UUID, now: Date = Date()) async throws -> PersonalStats {
        let weekAgo = now.addingTimeInterval(-Self.week)

        let sentTotal = try await Kudos.query(on: db)
            .filter(\.$fromEmployee.$id == employeeId)
            .count()
        let receivedTotal = try await Kudos.query(on: db)
            .filter(\.$employee.$id == employeeId)
            .count()
        let sentLastWeek = try await Kudos.query(on: db)
            .filter(\.$fromEmployee.$id == employeeId)
            .filter(\.$ts >= weekAgo)
            .count()
        let receivedLastWeek = try await Kudos.query(on: db)
            .filter(\.$employee.$id == employeeId)
            .filter(\.$ts >= weekAgo)
            .count()
        let reactionsOnSent = try await Kudos.query(on: db)
            .filter(\.$fromEmployee.$id == employeeId)
            .filter(\.$reaction != nil)
            .count()

        return PersonalStats(
            sentTotal: sentTotal,
            receivedTotal: receivedTotal,
            sentLastWeek: sentLastWeek,
            receivedLastWeek: receivedLastWeek,
            reactionsOnSent: reactionsOnSent
        )
    }

    // MARK: - Feed & jar

    /// Последние спасибо, где участник — отправитель или получатель (новые сверху)
    func recent(involving employeeId: UUID, limit: Int) async throws -> [Kudos] {
        try await Kudos.query(on: db)
            .group(.or) { or in
                or.filter(\.$employee.$id == employeeId)
                or.filter(\.$fromEmployee.$id == employeeId)
            }
            .with(\.$employee)
            .with(\.$fromEmployee)
            .sort(\.$ts, .descending)
            .limit(limit)
            .all()
    }

    /// Случайное спасибо из полученных участником («банка благодарностей»)
    func randomReceived(by employeeId: UUID, since: Date? = nil) async throws -> Kudos? {
        func base() -> QueryBuilder<Kudos> {
            let query = Kudos.query(on: db).filter(\.$employee.$id == employeeId)
            if let since { query.filter(\.$ts >= since) }
            return query
        }

        let total = try await base().count()
        guard total > 0 else { return nil }

        return try await base()
            .with(\.$employee)
            .with(\.$fromEmployee)
            .sort(\.$ts, .ascending)
            .offset(Int.random(in: 0..<total))
            .first()
    }

    // MARK: - Reminders & digest

    /// Отправлял ли участник спасибо сегодня (по календарю сервера)
    func hasSentToday(employeeId: UUID, now: Date = Date(), calendar: Calendar = .current) async throws -> Bool {
        let startOfDay = calendar.startOfDay(for: now)
        let count = try await Kudos.query(on: db)
            .filter(\.$fromEmployee.$id == employeeId)
            .filter(\.$ts >= startOfDay)
            .count()
        return count > 0
    }

    struct WeeklySummary {
        let sent: Int
        let received: Int
        /// Случайное спасибо, полученное за неделю, — чтобы напомнить о приятном
        let highlight: Kudos?
    }

    func weeklySummary(for employeeId: UUID, now: Date = Date()) async throws -> WeeklySummary {
        let weekAgo = now.addingTimeInterval(-Self.week)
        let sent = try await Kudos.query(on: db)
            .filter(\.$fromEmployee.$id == employeeId)
            .filter(\.$ts >= weekAgo)
            .count()
        let received = try await Kudos.query(on: db)
            .filter(\.$employee.$id == employeeId)
            .filter(\.$ts >= weekAgo)
            .count()
        let highlight = try await randomReceived(by: employeeId, since: weekAgo)
        return WeeklySummary(sent: sent, received: received, highlight: highlight)
    }

    // MARK: - Reactions

    enum ReactionOutcome {
        case reacted(Kudos)
        case alreadyReacted(String)
        case notRecipient
        case notFound
    }

    /// Сохраняет реакцию получателя. Отреагировать можно один раз и только на своё спасибо.
    func react(kudosId: UUID, byTelegramId telegramId: Int64, reaction: String) async throws -> ReactionOutcome {
        guard let kudos = try await Kudos.query(on: db)
            .filter(\.$id == kudosId)
            .with(\.$employee)
            .with(\.$fromEmployee)
            .first() else {
            return .notFound
        }

        guard kudos.employee?.telegramId == telegramId else {
            return .notRecipient
        }

        if let existing = kudos.reaction {
            return .alreadyReacted(existing)
        }

        kudos.reaction = reaction
        kudos.reactedAt = Date()
        try await kudos.save(on: db)
        return .reacted(kudos)
    }

    private static let week: TimeInterval = 7 * 24 * 3600
}
