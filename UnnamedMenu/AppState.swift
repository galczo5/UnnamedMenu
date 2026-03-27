import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var commands: [CommandItem] = []
    @Published var loadedFileNames: [String] = []

    func reload() {
        let result = MenuLoader.load()
        commands = result.items
        loadedFileNames = result.fileNames
    }
}
