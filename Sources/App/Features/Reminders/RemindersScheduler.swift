//
//  RemindersScheduler.swift
//  ChatBot
//
//  Created by Роман Пшеничников on 18.11.2025.
//

import Vapor

struct RemindersScheduler {

    static func setup(app: Application) {
        guard let times = Environment.get("REMINDER_TIMES")?
            .split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespaces) }),
              !times.isEmpty else {
            app.logger.info("RemindersScheduler: REMINDER_TIMES not set or empty, skipping reminders.")
            return
        }

        let service = RemindersService(app: app)

        app.logger.info("RemindersScheduler: initialized. times=\(times.joined(separator: ","))")
        
        // Проверка сообщением при запуске Docker контейнера
         app.logger.info("RemindersScheduler: sending startup reminder once...")
         service.sendRandomReminder()

        for time in times {
            app.logger.info("RemindersScheduler: scheduling reminder for \(time)")
            schedule(for: time, service: service, app: app)
        }
    }

    private static func schedule(for time: String,
                                 service: RemindersService,
                                 app: Application)
    {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            print("⚠️ Wrong REMINDER_TIMES format.")
            return
        }

        app.eventLoopGroup.next().scheduleRepeatedTask(
            initialDelay: .seconds(3),
            delay: .minutes(1)
        ) { _ in
            let now = Date()
            let cal = Calendar.current
            if cal.component(.hour, from: now) == hour &&
               cal.component(.minute, from: now) == minute {
                service.sendRandomReminder()
            }
        }
    }
}
