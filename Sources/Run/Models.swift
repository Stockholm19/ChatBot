import Vapor
import Fluent

final class Kudos: Model, Content {
    static let schema = "kudos"
    @ID(key: .id) var id: UUID?
    @Field(key: "ts") var ts: Date
    @Field(key: "from_user_id") var fromUserId: Int64
    @Field(key: "from_username") var fromUsername: String
    @Field(key: "from_name") var fromName: String
    @Field(key: "to_username") var toUsername: String
    @Field(key: "reason") var reason: String
    init() {}
    init(ts: Date, fromUserId: Int64, fromUsername: String, fromName: String, toUsername: String, reason: String) {
        self.ts = ts; self.fromUserId = fromUserId; self.fromUsername = fromUsername
        self.fromName = fromName; self.toUsername = toUsername; self.reason = reason
    }
}
struct CreateKudos: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema(Kudos.schema)
            .id()
            .field("ts", .datetime, .required)
            .field("from_user_id", .int64, .required)
            .field("from_username", .string, .required)
            .field("from_name", .string, .required)
            .field("to_username", .string, .required)
            .field("reason", .string, .required)
            .create()
    }
    func revert(on db: Database) async throws { try await db.schema(Kudos.schema).delete() }
}
