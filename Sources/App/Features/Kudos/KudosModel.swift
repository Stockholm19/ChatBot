//
//  KudosModel.swift
//  kudos-vapor
//
//  Модель благодарности (Kudos) и миграция для создания таблицы в БД.
//

import Vapor
import Fluent

/// Модель благодарности
final class Kudos: Model, Content, @unchecked Sendable {
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

    /// Связь с сотрудником через FK (nullable для обратной совместимости)
    @OptionalParent(key: "employee_id")
    var employee: Employee?

    /// Удобное поле для экспорта/отображения: если есть Employee — берём его имя, иначе username
    var recipientDisplayName: String {
        if let employeeName = employee?.fullName {
            return employeeName
        } else {
            return toUsername
        }
    }

    /// Связь с сотрудником-отправителем (nullable для совместимости)
    @OptionalParent(key: "from_employee_id")
    var fromEmployee: Employee?

    /// Имя отправителя для экспорта/отображения (если привязан сотрудник — используем его ФИО)
    var senderDisplayName: String {
        if let name = fromEmployee?.fullName {
            return name
        } else {
            return fromName
        }
    }

    /// Причина благодарности (текст)
    @Field(key: "reason") var reason: String

    init() {}

    init(ts: Date,
         fromUserId: Int64,
         fromUsername: String,
         fromName: String,
         toUsername: String,
         reason: String,
         employeeId: UUID? = nil,
         fromEmployeeId: UUID? = nil) {
        self.ts = ts
        self.fromUserId = fromUserId
        self.fromUsername = fromUsername
        self.fromName = fromName
        self.toUsername = toUsername
        self.reason = reason
        // nullable FK for обратной совместимости (получатель)
        self.$employee.id = employeeId
        // nullable FK для отправителя
        self.$fromEmployee.id = fromEmployeeId
    }
}

/// Миграция: добавить колонку employee_id (nullable) и FK → employees(id)
struct AddEmployeeIdToKudos: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema(Kudos.schema)
            .field("employee_id", .uuid,
                   .references(Employee.schema, .id, onDelete: .setNull))
            .update()
    }

    func revert(on db: Database) async throws {
        try await db.schema(Kudos.schema)
            .deleteField("employee_id")
            .update()
    }
}

/// Миграция: добавить колонку from_employee_id (nullable) и FK → employees(id)
struct AddFromEmployeeIdToKudos: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema(Kudos.schema)
            .field("from_employee_id", .uuid,
                   .references(Employee.schema, .id, onDelete: .setNull))
            .update()
    }

    func revert(on db: Database) async throws {
        try await db.schema(Kudos.schema)
            .deleteField("from_employee_id")
            .update()
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
