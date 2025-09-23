//
//  KudosModel.swift
//  kudos-vapor
//
//  Модель благодарности (Kudos) и миграция для создания таблицы в БД.
//

import Vapor
import Fluent

/// Модель благодарности
final class Kudos: Model, Content {
    static let schema = "kudos"   // имя таблицы в базе

    @ID(key: .id) var id: UUID?

    /// Дата и время благодарности
    @Field(key: "ts") var ts: Date

    /// ID пользователя-отправителя (из Telegram)
    @Field(key: "from_user_id") var fromUserId: Int64

    /// Telegram username отправителя
    @Field(key: "from_username") var fromUsername: String

    /// Отображаемое имя отправителя
    @Field(key: "from_name") var fromName: String

    /// Username получателя благодарности
    @Field(key: "to_username") var toUsername: String

    /// Причина благодарности (текст)
    @Field(key: "reason") var reason: String

    init() {}

    init(ts: Date, fromUserId: Int64, fromUsername: String, fromName: String, toUsername: String, reason: String) {
        self.ts = ts
        self.fromUserId = fromUserId
        self.fromUsername = fromUsername
        self.fromName = fromName
        self.toUsername = toUsername
        self.reason = reason
    }
}

/// Миграция для создания таблицы kudos
struct CreateKudos: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema(Kudos.schema)
            .id()
            .field("ts", .datetime, .required)
            .field("from_user_id", .int64, .required)
            .field("from_username", .string, .required)
            .field("from_name", .string, .required)
            .field("to_username", .string, .required)
            .field("reason", .string, .required)
            .create()
    }

    func revert(on db: Database) async throws {
        try await db.schema(Kudos.schema).delete()
    }
}
