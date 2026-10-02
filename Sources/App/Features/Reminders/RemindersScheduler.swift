//
//  RemindersScheduler.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 18.11.2025.
//

import Vapor

struct RemindersScheduler {

    static func setup(app: Application) {
        let times = ClockScheduler.TimeOfDay.list(Environment.get("REMINDER_TIMES"))
        guard !times.isEmpty else {
            app.logger.info("RemindersScheduler: REMINDER_TIMES not set or empty, skipping reminders.")
            return
        }
        guard let api = TelegramService.apiBaseURL() else {
            app.logger.warning("RemindersScheduler: BOT_TOKEN is empty, skipping reminders.")
            return
        }

        let service = RemindersService(
            app: app,
            api: api,
            messages: RemindersService.loadMessages(app: app)
        )

        for time in times {
            app.logger.info("RemindersScheduler: scheduling personal reminders at \(time.hour):\(String(format: "%02d", time.minute))")
            ClockScheduler.schedule(app: app, at: time) {
                await service.sendReminders()
            }
        }
    }
}
