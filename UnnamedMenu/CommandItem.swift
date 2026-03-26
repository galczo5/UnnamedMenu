import Foundation

struct CommandItem: Identifiable {
    let id = UUID()
    let name: String
    let command: String
    let systemImage: String

    static let defaults: [CommandItem] = [
        .init(name: "List Home",          command: "ls -la ~",       systemImage: "folder"),
        .init(name: "Disk Usage",         command: "df -h",          systemImage: "internaldrive"),
        .init(name: "Top Processes",      command: "top -l 1 -n 5",  systemImage: "cpu"),
        .init(name: "Network Interfaces", command: "ifconfig",       systemImage: "network"),
        .init(name: "Running Processes",  command: "ps aux",         systemImage: "list.bullet"),
        .init(name: "Uptime",             command: "uptime",         systemImage: "clock"),
        .init(name: "Environment",        command: "env",            systemImage: "text.alignleft"),
        .init(name: "Who Is Logged In",   command: "who",            systemImage: "person.fill"),
    ]
}
