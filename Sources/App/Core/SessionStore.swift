//
//  SessionStore.swift
//  kudos-vapor
//
//  Потокобезопасное хранилище сессий для чатов Telegram.
//  Нужно для пошаговых диалогов (например, команда /thanks).
//

import Foundation

/// Состояние диалога для конкретного чата (например, кому сказать спасибо).
public struct Session {
    public var to: String?
    public init(to: String? = nil) { self.to = to }
}

/// Простое in-memory хранилище на основе actor.
/// Данные живут только пока работает процесс.
/// Если нужна долговременная память — перенеси это в БД.
public actor SessionStore {
    private var sessions: [Int64: Session] = [:]
    public init() {}

    /// Получить сессию для чата
    public func get(_ chatId: Int64) -> Session? {
        sessions[chatId]
    }

    /// Установить/обновить сессию для чата
    public func set(_ chatId: Int64, _ session: Session?) {
        sessions[chatId] = session
    }
}
