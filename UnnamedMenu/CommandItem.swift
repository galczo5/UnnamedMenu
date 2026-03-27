import Foundation

struct CommandItem: Identifiable, Decodable {
    let id = UUID()
    let name: String
    let command: String
    let systemImage: String

    private enum CodingKeys: String, CodingKey {
        case name, command, systemImage
    }
}
