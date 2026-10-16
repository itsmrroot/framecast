import SwiftUI
import AppKit

/// One action in the command palette.
struct PaletteCommand: Identifiable {
    let id: String
    let group: String
    let title: String
    let icon: String
    var shortcut: String? = nil
    var hint: String? = nil
    /// For toggles: whether it's on (shows a checkmark).
    var isOn: Bool? = nil
    var enabled = true
    let run: () -> Void
}

/// Searchable list of every editor command (⌘K). ↑/↓ to move, ↩ to run, Esc to close.
struct CommandPaletteView: View {
    let commands: [PaletteCommand]
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var filtered: [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let enabled = commands.filter(\.enabled)
        guard !q.isEmpty else { return enabled }
        let words = q.split(separator: " ")
        return enabled.filter { c in
            let hay = "\(c.title) \(c.group) \(c.hint ?? "")".lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    var body: some View {
        let items = filtered
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textDim)
                TextField("Type to find a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { run(items) }
                    .onChange(of: query) { _, _ in highlighted = 0 }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                            if i == 0 || items[i - 1].group != c.group {
                                Text(c.group)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.textFaint)
                                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                            }
                            row(c, highlighted: i == highlighted)
                                .id(c.id)
                                .onTapGesture { highlighted = i; run(items) }
                        }
                        if items.isEmpty {
                            Text("No matching commands").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                                .frame(maxWidth: .infinity).padding(30)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .onChange(of: highlighted) { _, i in
                    if items.indices.contains(i) { proxy.scrollTo(items[i].id) }
                }
            }
        }
        .frame(width: 580, height: 440)
        .background(Theme.panel)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(0, items.count - 1)); return .handled }
        .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
        .onExitCommand { isPresented = false }
    }

    private func row(_ c: PaletteCommand, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: c.icon).frame(width: 20).foregroundStyle(Theme.textDim)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title).font(.system(size: 13))
                if let hint = c.hint { Text(hint).font(.system(size: 11)).foregroundStyle(Theme.textDim) }
            }
            Spacer()
            if c.isOn == true { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent) }
            if let s = c.shortcut {
                Text(s)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.fill.opacity(0.08)))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(highlighted ? Theme.accent.opacity(0.22) : .clear).padding(.horizontal, 6))
        .contentShape(Rectangle())
    }

    private func run(_ items: [PaletteCommand]) {
        guard items.indices.contains(highlighted) else { return }
        let c = items[highlighted]
        isPresented = false
        // Let the sheet close before running (some commands open their own sheet).
        DispatchQueue.main.async { c.run() }
    }
}
