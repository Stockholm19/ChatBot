//
//  PendingLink.swift
//  ChatBot
//
//  Created by opencode on 20.01.2026.
//

import Fluent
import Vapor

final class PendingLink: Model, Content, @unchecked Sendable {
    static let schema = "pending_links"

    @ID(key: .id) var id: UUID?

    @Field(key: "code") var code: String
    @Parent(key: "employee_id") var employee: Employee
    @OptionalField(key: "created_by_admin_tg_id") var createdByAdminTgId: Int64?
    @Field(key: "is_used") var isUsed: Bool
    
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Field(key: "expires_at") var expiresAt: Date
    @OptionalField(key: "used_at") var usedAt: Date?

    init() { }

    init(id: UUID? = nil, 
         code: String, 
         employeeId: UUID, 
         createdByAdminTgId: Int64? = nil, 
         expiresAt: Date,
         isUsed: Bool = false) {
        self.id = id
        self.code = code
        self.$employee.id = employeeId
        self.createdByAdminTgId = createdByAdminTgId
        self.expiresAt = expiresAt
        self.isUsed = isUsed
    }
}

extension PendingLink {
    /// Удаляет просроченные или старые использованные заявки
    static func cleanupExpired(on db: Database) async throws -> Int {
        let now = Date()
        // Удаляем просроченные
        let expired = try await PendingLink.query(on: db)
            .group(.or) { or in
                or.filter(\.$expiresAt < now)
                or.group(.and) { and in
                    and.filter(\.$isUsed == true)
                    // Удаляем использованные старше 1 дня
                    if let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now) {
                        and.filter(\.$usedAt < oneDayAgo)
                    }
                }
            }
            .all()
        
        let count = expired.count
        for item in expired {
            try await item.delete(on: db)
        }
        return count
    }
}

struct CreatePendingLinks: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema(PendingLink.schema)
            .id()
            .field("code", .string, .required)
            .field("employee_id", .uuid, .required, .references(Employee.schema, "id", onDelete: .cascade))
            .field("created_by_admin_tg_id", .int64)
            .field("is_used", .bool, .required)
            .field("created_at", .datetime)
            .field("expires_at", .datetime, .required)
            .field("used_at", .datetime)
            .unique(on: "code")
            .create()
    }

    func revert(on db: Database) async throws {
        try await db.schema(PendingLink.schema).delete()
    }
}
