//
//  Routes.swift
//  kudos-vapor
//
//  Created by Роман Пшеничников on 23.09.2025.
//

import Vapor

public func routes(_ app: Application) throws {
    // Подключаем роуты фич (пока заглушки, чтобы структура была единообразной)
    try app.kudosRoutes()
    try app.exportRoutes()

    // Healthcheck для Docker/мониторинга
    app.get("health") { _ in "ok" }
}

// MARK: - Feature routes stubs

extension Application {
    func kudosRoutes() throws {
        
        // HTTP-роутов у бота может не быть — поэтому пока заглушка,
        // чтобы при необходимости быстро добавить эндпоинты.
        // Пример:
        // self.get("kudos") { req async throws -> [Kudos] in
        //     try await Kudos.query(on: req.db).all()
        // }
        
    }

    func exportRoutes() throws {
        // Здесь можно добавить HTTP-эндпоинт для скачивания CSV,
        // если когда-нибудь понадобится веб-доступ к отчетам.
        // Но пока достаточно отправки CSV напрямую в Telegram.
    }
}
