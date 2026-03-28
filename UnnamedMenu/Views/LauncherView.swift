import SwiftUI
import AppKit

private struct WindowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct LauncherView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var debounceTask: DispatchWorkItem? = nil
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    private var maxResults: Int {
        (appState.showAll || appState.windowsMode) ? 25 : 5
    }

    var filteredCommands: [CommandItem] {
        if debouncedSearch.isEmpty {
            return (appState.showAll || appState.windowsMode) ? Array(appState.visibleCommands.prefix(maxResults)) : []
        }
        let scored = appState.visibleCommands
            .compactMap { item -> (score: Double, item: CommandItem)? in
                let nameScore = FuzzyMatcher.score(query: debouncedSearch, in: item.name)
                let cmdScore  = FuzzyMatcher.score(query: debouncedSearch, in: item.command)
                guard let best = [nameScore, cmdScore].compactMap({ $0 }).max() else { return nil }
                return (best, item)
            }
            .sorted { $0.score > $1.score }
        return Array(scored.prefix(maxResults).map { $0.item })
    }

    var body: some View {
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
                    .onChange(of: searchText) {
                        selectedIndex = 0
                        debounceTask?.cancel()
                        let task = DispatchWorkItem { debouncedSearch = searchText }
                        debounceTask = task
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // Command list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, item in
                            CommandRow(item: item, isSelected: index == selectedIndex)
                                .id(item.id)
                                .onTapGesture {
                                    selectedIndex = index
                                    runSelected()
                                }
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(filteredCommands.count) * 46, CGFloat(maxResults) * 46))
                .onChange(of: selectedIndex) { _, newIndex in
                    guard filteredCommands.indices.contains(newIndex) else { return }
                    withAnimation {
                        proxy.scrollTo(filteredCommands[newIndex].id, anchor: nil)
                    }
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: WindowHeightKey.self, value: geo.size.height)
            }
        )
        .background(VisualEffectView())
        .frame(width: 600)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onPreferenceChange(WindowHeightKey.self) { height in
            guard height > 0, let window = NSApp.keyWindow else { return }
            var frame = window.frame
            frame.origin.y += frame.height - height
            frame.size.height = height
            window.setFrame(frame, display: true, animate: false)
        }
        .onAppear {
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            searchText = ""
            debouncedSearch = ""
            debounceTask?.cancel()
            selectedIndex = 0
            isSearchFocused = true
        }
        .onKeyPress(.upArrow)   { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(+1); return .handled }
        .onKeyPress(.escape)    { hideWindow();      return .handled }
        .onReceive(NotificationCenter.default.publisher(for: .menuCycleSelection)) { _ in moveSelection(+1) }
        .onReceive(NotificationCenter.default.publisher(for: .menuRunSelected)) { _ in runSelected() }
    }

    private func moveSelection(_ delta: Int) {
        let count = filteredCommands.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func runSelected() {
        guard filteredCommands.indices.contains(selectedIndex) else { return }
        let item = filteredCommands[selectedIndex]
        print("[runSelected] name=\"\(item.name)\" pid=\(item.pid ?? "nil") wid=\(item.wid ?? "nil") windowTitle=\(item.windowTitle ?? "nil")")
        hideWindow()
        if let pidStr = item.pid, let pid = pid_t(pidStr) {
            let wid = CGWindowID(item.wid ?? "0") ?? 0
            WindowFocuser.focus(pid: pid, windowTitle: item.windowTitle ?? "", targetWid: wid)
        } else {
            try? CommandRunner.run(item.command)
        }
    }

    private func hideWindow() {
        KeybindingService.shared.clearHeldModifiers()
        appState.clearFilter()
        NSApp.keyWindow?.close()
    }
}

private struct CommandRow: View {
    let item: CommandItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if item.systemImage.hasPrefix("/") {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.systemImage))
                    .resizable()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: item.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(isSelected ? .white : Color(nsColor: .secondaryLabelColor))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : Color(nsColor: .labelColor))
                Text(item.command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : Color.clear)
    }
}

#Preview {
    LauncherView()
        .environmentObject(AppState())
}
