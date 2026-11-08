import SwiftUI

struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    @Binding var isTargeted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.white.opacity(0.18))

            if shelf.items.isEmpty {
                EmptyStateView(
                    symbol: "tray.and.arrow.down",
                    title: "Drop files here",
                    subtitle: "Drag them back out when you need them."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItemView(url: url, shelf: shelf)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .onAppear { shelf.pruneMissing() }
    }
}

struct ShelfItemView: View {
    let url: URL
    @ObservedObject var shelf: ShelfStore

    private var path: String { url.path(percentEncoded: false) }

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 48, height: 48)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 68)
        }
        .padding(6)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: url as NSURL) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
        .help(path)
    }
}

struct ShelfClearButton: View {
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        if !shelf.items.isEmpty {
            Button("Clear") { shelf.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
