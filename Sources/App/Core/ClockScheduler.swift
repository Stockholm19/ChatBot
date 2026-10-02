//
//  ClockScheduler.swift
//  ChatBot
//
//  Запуск фоновых действий в заданное время суток (по часовому поясу сервера, переменная TZ).
//  Используется напоминаниями и итогами недели. В тестах не запускается (см. Boot.swift).
//

import Vapor

enum ClockScheduler {

    /// Время суток в формате HH:mm
    struct TimeOfDay: Equatable {
        let hour: Int
        let minute: Int

        init?(_ raw: String) {
            let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]), (0..<24).contains(hour),
                  let minute = Int(parts[1]), (0..<60).contains(minute) else {
                return nil
            }
            self.hour = hour
            self.minute = minute
        }

        /// Разбирает список вида "10:00, 21:30"; некорректные значения пропускаются
        static func list(_ raw: String?) -> [TimeOfDay] {
            (raw ?? "")
                .split(separator: ",")
                .compactMap { TimeOfDay(String($0)) }
        }
    }

    /// Проверяет раз в минуту, не наступило ли нужное время, и запускает `action`.
    /// - Parameter weekday: день недели по `Calendar` (1 — воскресенье … 7 — суббота); nil — каждый день
    static func schedule(
        app: Application,
        at time: TimeOfDay,
        weekday: Int? = nil,
        action: @escaping @Sendable () async -> Void
    ) {
        app.eventLoopGroup.next().scheduleRepeatedTask(
            initialDelay: .seconds(3),
            delay: .minutes(1)
        ) { _ in
            let now = Date()
            let cal = Calendar.current
            guard cal.component(.hour, from: now) == time.hour,
                  cal.component(.minute, from: now) == time.minute else {
                return
            }
            if let weekday, cal.component(.weekday, from: now) != weekday {
                return
            }
            Task { await action() }
        }
    }
}
