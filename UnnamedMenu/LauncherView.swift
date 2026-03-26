import SwiftUI
import AppKit

struct LauncherView: View {
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var outputText = ""
    @FocusState private var isSearchFocused: Bool

    var filteredCommands: [CommandItem] {
        guard !searchText.isEmpty else { return CommandItem.defaults }
        return CommandItem.defaults.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            VisualEffectView()

            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18, weight: .medium))

                    TextField("Search commands…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .focused($isSearchFocused)
                        .onSubmit { runSelected() }
                        .onChange(of: searchText) { selectedIndex = 0 }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                // Command list
                ScrollViewReader { proxy in
                    List(Array(filteredCommands.enumerated()), id: \.element.id) { index, item in
                        CommandRow(item: item, isSelected: index == selectedIndex)
                            .id(item.id)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                            .listRowBackground(Color.clear)
                            .onTapGesture {
                                selectedIndex = index
                                runSelected()
                            }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: 270)
                    .onChange(of: selectedIndex) { _, newIndex in
                        guard filteredCommands.indices.contains(newIndex) else { return }
                        withAnimation {
                            proxy.scrollTo(filteredCommands[newIndex].id, anchor: nil)
                        }
                    }
                }

                // Output area
                if !outputText.isEmpty {
                    Divider()
                    ScrollView {
                        Text(outputText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(height: 120)
                }
            }
        }
        .frame(width: 600)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { isSearchFocused = true }
        .onKeyPress(.upArrow)   { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(+1); return .handled }
        .onKeyPress(.escape)    { hideWindow();      return .handled }
    }

    private func moveSelection(_ delta: Int) {
        let count = filteredCommands.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func runSelected() {
        guard filteredCommands.indices.contains(selectedIndex) else { return }
        let command = filteredCommands[selectedIndex].command
        Task.detached {
            let result = (try? CommandRunner.run(command)) ?? "(no output)"
            await MainActor.run { outputText = result }
        }
    }

    private func hideWindow() {
        NSApp.keyWindow?.close()
    }
}

private struct CommandRow: View {
    let item: CommandItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .frame(width: 22)
                .foregroundStyle(isSelected ? .white : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(item.command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}

#Preview {
    LauncherView()
}
