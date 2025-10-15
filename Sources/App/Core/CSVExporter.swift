//
//  CSVExporter.swift
//  kudos-vapor
//
//  Экспорт благодарностей в CSV-файл (с разделителем `;`).
//  Используется командой /export в Telegram.
//

import Vapor
import Fluent
import Foundation

enum CSVExporter {
    
    /// Экспорт всех записей Kudos в CSV-файл по указанному пути
    static func exportKudos(db: Database, to path: String) async throws {
        
        // Загружаем все записи Kudos из БД, сортируем по времени
        let rows = try await Kudos.query(on: db).sort(\.$ts, .ascending).all()
        let delimiter = ";"

        // Заголовки CSV
        var csv = "Дата и время\(delimiter)От кого (логин)\(delimiter)От кого (имя)\(delimiter)Кому (логин)\(delimiter)Причина\n"
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "dd.MM.yyyy HH:mm"
        
        // Часовой пояс фиксируем как +3 часа от UTC (Москва)
        df.timeZone = TimeZone(secondsFromGMT: 3 * 3600)

        // Функция экранирования: заменяем кавычки и оборачиваем в кавычки при необходимости
        func esc(_ s: String) -> String {
            var v = s.replacingOccurrences(of: "\"", with: "\"\"")
            if v.contains(delimiter) || v.contains("\n") || v.contains("\r") {
                v = "\"\(v)\""
            }
            return v
        }

        // Формируем строки CSV для каждой записи
        for k in rows {
            csv += [
                esc(df.string(from: k.ts)),
                esc(k.fromUsername),
                esc(k.fromName),
                esc(k.toUsername),
                esc(k.reason)
            ].joined(separator: delimiter) + "\n"
        }

        // Добавляем BOM для корректного открытия в Excel (Windows)
        let final = "\u{FEFF}" + csv
        try final.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}
