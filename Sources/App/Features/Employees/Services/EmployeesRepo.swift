//
//  EmployeesRepo.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 20.10.2025.
//

import Fluent

// Интерфейс
protocol EmployeesRepo {
    func page(_ page: Int, per: Int) async throws -> (items: [Employee], total: Int)
    func search(_ q: String, page: Int, per: Int) async throws -> (items: [Employee], total: Int)
    func get(_ id: UUID) async throws -> Employee?
}

struct FluentEmployeesRepo: EmployeesRepo {
    let db: Database

    func page(_ page: Int, per: Int) async throws -> (items: [Employee], total: Int) {
        let total = try await Employee.query(on: db).filter(\.$isActive == true).count()
        let items = try await Employee.query(on: db)
            .filter(\.$isActive == true)
            .sort(\.$fullName, .ascending)
            .range((page - 1) * per ..< page * per)
            .all()
        return (items, total)
    }

    func search(_ q: String, page: Int, per: Int) async throws -> (items: [Employee], total: Int) {
        let pattern = "%\(q)%"
        let base = Employee.query(on: db)
            .filter(\.$isActive == true)
            .group(.or) {
                $0.filter(\.$fullName, .custom("ILIKE"), pattern)
                $0.filter(\.$position, .custom("ILIKE"), pattern)
            }

        let total = try await base.count()
        let items = try await base
            .sort(\.$fullName, .ascending)
            .range((page - 1) * per ..< page * per)
            .all()
        return (items, total)
    }

    func get(_ id: UUID) async throws -> Employee? {
        try await Employee.find(id, on: db)
    }
}
