//
//  SessionStore.swift
//  kudos-vapor
//
//  Потокобезопасное хранилище сессий для чатов Telegram.
//  Нужно для пошаговых диалогов (например, команда /thanks).
//

import Foundation

/// 1. Возможные состояния диалога (в каком месте меню/сценария находится пользователь)
public enum SessionState: String, Codable {
    case mainMenu
    case thanksMenu
    case statisticsMenu
    case choosingEmployee
    case awaitingRecipient
    case awaitingReason
    case adminMenu
    
    // Admin: Add Employee
    case adminAddAskName
    case adminAddConfirmName
    case adminAddAskForward
    case adminAddConfirmAccount
    
    // Admin: Deactivate
    case adminDeactivateChoose
    case adminDeactivateConfirm
    
    // Admin: Archive
    case adminArchiveChoose
    case adminArchiveConfirm
    
    // Admin: Link Telegram
    case adminLinkChoose
}

/// 2. Данные одной сессии (сохраняем состояние и, например, выбранного получателя)
public struct Session: Codable {
    public var state: SessionState
    public var to: String?
    public var page: Int?
    public var chosenEmployeeId: UUID?
    
    // New fields for Admin Flow
    public var draftFullName: String?
    public var draftTelegramId: Int64?
    public var selectedEmployeeId: UUID?

    public init(state: SessionState = .mainMenu, 
                to: String? = nil, 
                page: Int? = nil, 
                chosenEmployeeId: UUID? = nil,
                draftFullName: String? = nil,
                draftTelegramId: Int64? = nil,
                selectedEmployeeId: UUID? = nil) {
        self.state = state
        self.to = to
        self.page = page
        self.chosenEmployeeId = chosenEmployeeId
        self.draftFullName = draftFullName
        self.draftTelegramId = draftTelegramId
        self.selectedEmployeeId = selectedEmployeeId
    }
}

/// 3. Хранилище всех сессий (in-memory словарь [chatId: Session], actor = потокобезопасность)
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
