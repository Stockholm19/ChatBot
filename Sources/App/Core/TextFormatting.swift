//
//  TextFormatting.swift
//  ChatBot
//
//  Хелперы для безопасного вывода пользовательского текста в сообщениях Telegram (parse_mode=HTML).
//

import Foundation

extension String {
    /// Экранирует спецсимволы HTML, чтобы пользовательский текст не ломал разметку Telegram
    var htmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Обрезает строку до `limit` символов, добавляя многоточие
    func truncated(to limit: Int) -> String {
        count > limit ? String(prefix(limit)) + "…" : self
    }
}
