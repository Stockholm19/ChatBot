//
//  Employee.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 20.10.2025.
//

import Fluent
import Vapor

final class Employee: Model, Content, @unchecked Sendable {
    static let schema = "employees"

    @ID(custom: "id") var id: UUID?
    @Field(key: "full_name") var fullName: String
    @OptionalField(key: "position") var position: String?
    @Field(key: "is_active") var isActive: Bool
    /// Telegram ID сотрудника (опционально, уникально)
    @OptionalField(key: "telegram_id") var telegramId: Int64?

    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() { }

    init(id: UUID? = nil, fullName: String, position: String? = nil, isActive: Bool = true) {
        self.id = id
        self.fullName = fullName
        self.position = position
        self.isActive = isActive
    }
}

struct AddTelegramIdToEmployees: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema(Employee.schema)
            .field("telegram_id", .int64)
            .unique(on: "telegram_id")
            .update()
    }

    func revert(on db: Database) async throws {
        try await db.schema(Employee.schema)
            .deleteField("telegram_id")
            .update()
    }
}
