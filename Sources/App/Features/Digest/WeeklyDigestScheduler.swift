//
//  WeeklyDigestScheduler.swift
//  ChatBot
//
//  Итоги недели по воскресеньям. Время — WEEKLY_DIGEST_TIME (HH:mm, по умолчанию 20:00),
//  значение `off` отключает итоги.
//

import Vapor

struct WeeklyDigestScheduler {

    static let defaultTime = "20:00"
    /// Воскресенье в нумерации `Calendar` (1 — воскресенье)
    static let sunday = 1

    static func setup(app: Application) {
        let raw = Environment.get("WEEKLY_DIGEST_TIME")?.trimmingCharacters(in: .whitespaces) ?? ""
        if raw.lowercased() == "off" {
            app.logger.info("WeeklyDigestScheduler: disabled via WEEKLY_DIGEST_TIME=off.")
            return
        }
        guard let time = ClockScheduler.TimeOfDay(raw.isEmpty ? defaultTime : raw) else {
            app.logger.warning("WeeklyDigestScheduler: wrong WEEKLY_DIGEST_TIME format: \(raw)")
            return
        }
        guard let api = TelegramService.apiBaseURL() else {
            app.logger.warning("WeeklyDigestScheduler: BOT_TOKEN is empty, skipping digest.")
            return
        }

        let service = WeeklyDigestService(app: app, api: api)
        app.logger.info("WeeklyDigestScheduler: scheduling Sunday digest at \(time.hour):\(String(format: "%02d", time.minute))")
        ClockScheduler.schedule(app: app, at: time, weekday: sunday) {
            await service.sendDigests()
        }
    }
}
