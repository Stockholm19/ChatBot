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
    @Field(key: "position") var position: String?
    @Field(key: "is_active") var isActive: Bool

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
