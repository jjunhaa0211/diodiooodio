import Foundation

struct EffectPreset: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var chainConfigJSON: String

    init(id: UUID = UUID(), name: String, chainConfigJSON: String) {
        self.id = id
        self.name = name
        self.chainConfigJSON = chainConfigJSON
    }
}
