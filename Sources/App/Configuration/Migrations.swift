//
//  Migrations.swift
//  kudos-vapor
//
//  Created by Роман Пшеничников on 23.09.2025.
//

import Vapor
import Fluent

public func migrations(_ app: Application) {
    // Регистрация миграций моделей
    app.migrations.add(CreateKudos())
    
    app.migrations.add(CreateEmployees())
    
    app.migrations.add(AddTelegramIdToEmployees())
    app.migrations.add(AddEmployeeIdToKudos())
    app.migrations.add(AddFromEmployeeIdToKudos())
}
