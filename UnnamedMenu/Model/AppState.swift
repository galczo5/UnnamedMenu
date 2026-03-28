import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var commands: [CommandItem] = []
    @Published var loadedFileNames: [String] = []
    @Published var activeFilter: URL? = nil
    @Published var pipedItems: [CommandItem]? = nil
    @Published var showAll: Bool = false
    @Published var windowsMode: Bool = false
    @Published var noSearch: Bool = false

    private var itemsByURL: [URL: [CommandItem]] = [:]

    var visibleCommands: [CommandItem] {
        if let piped = pipedItems        { return piped }
        if let filter = activeFilter     { return itemsByURL[filter] ?? [] }
        return commands
    }

    func reload() {
        let result = MenuLoader.load()
        commands = result.items
        loadedFileNames = result.fileNames
        itemsByURL = result.itemsByURL
    }

    func applyFilter(url: URL) {
        if itemsByURL[url] == nil {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([CommandItem].self, from: data) {
                itemsByURL[url] = decoded
            }
        }
        activeFilter = url
    }

    func applyItems(_ items: [CommandItem]) {
        pipedItems = items
    }

    func clearFilter() {
        activeFilter = nil
        pipedItems = nil
        showAll = false
        windowsMode = false
        noSearch = false
    }
}
