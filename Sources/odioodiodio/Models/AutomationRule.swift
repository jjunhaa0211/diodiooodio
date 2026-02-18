import Foundation

struct AutomationRule: Identifiable, Hashable, Codable {
    let id: UUID
    var trigger: Trigger
    var conditions: [Condition]
    var actions: [Action]

    init(
        id: UUID = UUID(),
        trigger: Trigger,
        conditions: [Condition],
        actions: [Action]
    ) {
        self.id = id
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
    }

    enum Trigger: String, Codable {
        case appLaunched
        case appTerminated
        case deviceConnected
        case deviceDisconnected
        case time
    }

    struct Condition: Hashable, Codable {
        var key: String
        var value: String
    }

    struct Action: Hashable, Codable {
        var kind: String
        var payload: String
    }
}
