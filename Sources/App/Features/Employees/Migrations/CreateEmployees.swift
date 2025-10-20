//
//  CreateEmployees.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 20.10.2025.
//

import Fluent

struct CreateEmployees: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema("employees")
            .id() // UUID PK
            .field("full_name", .string, .required)
            .field("position", .string)
            .field("is_active", .bool, .required, .sql(.default(true)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on db: Database) async throws {
        try await db.schema("employees").delete()
    }
}
