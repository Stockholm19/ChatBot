import App
import Vapor

@main
struct RunApp {
    static func main() async throws {
        let env = try Environment.detect()
        let app = try await Application.make(env)

        do {
            // Конфигурация приложения (БД, миграции, роуты)
            try configure(app)

            // Общее хранилище сессий для бота
            let sessions = SessionStore()

            // Запускаем фоновую задачу для обработки сообщений Telegram
            Task { await TelegramService.poll(app: app, sessions: sessions) }

            // Запуск HTTP-сервера Vapor
            try await app.execute()
            try await app.asyncShutdown()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
    }
}
