
import Fluent
import SQLKit

struct AddCreatedAtToEmployees: AsyncMigration {
    func prepare(on db: Database) async throws {
        guard let sql = db as? SQLDatabase else {
            return
        }
        
        // 1. Добавляем колонку, если ее нет
        try await sql.raw("ALTER TABLE employees ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW()").run()
        
        // 2. Backfill: заполняем NULL значения
        try await sql.raw("UPDATE employees SET created_at = NOW() WHERE created_at IS NULL").run()
        
        // 3. Устанавливаем NOT NULL и DEFAULT
        try await sql.raw("ALTER TABLE employees ALTER COLUMN created_at SET NOT NULL").run()
        try await sql.raw("ALTER TABLE employees ALTER COLUMN created_at SET DEFAULT NOW()").run()
    }

    func revert(on db: Database) async throws {
        guard let sql = db as? SQLDatabase else {
            return
        }
        try await sql.raw("ALTER TABLE employees ALTER COLUMN created_at DROP NOT NULL").run()
    }
}
