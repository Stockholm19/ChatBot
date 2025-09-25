import App
import Vapor

@main
struct RunApp {
    static func main() throws {
        let env = try Environment.detect()
        let app = Application(env)
        defer { app.shutdown() }

        // Конфигурация приложения (БД, миграции, роуты)
        try configure(app)

        // Общее хранилище сессий для бота
        let sessions = SessionStore()

        // Запускаем фоновую задачу для обработки сообщений Telegram
        Task { await TelegramService.poll(app: app, sessions: sessions) }

        // Запуск HTTP-сервера Vapor
        try app.run()
    }
}
