import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var shelf: ShelfManager
    @State private var shelfTargeted = false
    @State private var airDropTargeted = false

    var body: some View {
        if shelf.dropTargeting {
            DropZones(shelf: shelf)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            HStack(spacing: 12) {
                tray
                sidebar.frame(width: 104)
            }
            .transition(.opacity)
        }
    }

    private var tray: some View {
        Group {
            if shelf.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26))
                    Text(tr("ลากไฟล์มาวางที่นี่", "Drop files here"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(shelfTargeted ? 0.9 : 0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items) { item in
                            ShelfItemView(item: item, shelf: shelf)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(shelfTargeted ? 0.6 : 0.15),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .onDrop(of: [.fileURL, .image], isTargeted: $shelfTargeted) { providers in
            shelf.add(providers: providers)
        }
    }

    /// With items picked: what to do with them. Otherwise: the AirDrop box and whole-shelf actions.
    @ViewBuilder private var sidebar: some View {
        let picked = shelf.selection.count
        VStack(spacing: 6) {
            if picked > 0 {
                Text(tr("เลือก \(picked) ไฟล์", "\(picked) selected"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                DragOutHandle(urls: shelf.selectedOrAll, label: tr("ลากออก", "Drag out")) { shelf.remove($0) }
                    .frame(height: 26)
                Button("AirDrop") { shelf.airDrop(shelf.selectedOrAll) }
                    .buttonStyle(PillButtonStyle())
                Button(tr("บีบอัด zip", "Zip")) { shelf.zip(shelf.selectedOrAll) }
                    .buttonStyle(PillButtonStyle())
                Button(tr("ยกเลิกเลือก", "Deselect")) { shelf.selection.removeAll() }
                    .buttonStyle(PillButtonStyle())
            } else {
                airDropTarget
                if shelf.items.count >= 2 {
                    DragOutHandle(urls: shelf.selectedOrAll, label: tr("ลากทั้งหมด", "Drag all")) { shelf.remove($0) }
                        .frame(height: 26)
                }
                if !shelf.items.isEmpty {
                    Button(tr("ล้าง", "Clear")) { shelf.clear() }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
    }

    private var airDropTarget: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .medium))
            Text("AirDrop")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(airDropTargeted ? Color.white : Color.white.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.blue.opacity(airDropTargeted ? 0.55 : 0.18))
        )
        .contentShape(Rectangle())
        .onTapGesture { shelf.airDrop(shelf.items.map(\.url)) }
        .help(tr("ลากไฟล์มาวางเพื่อส่ง AirDrop หรือคลิกเพื่อส่งทุกไฟล์บนชั้นวาง", "Drop files to AirDrop them, or click to AirDrop the whole shelf"))
        .onDrop(of: [.fileURL], isTargeted: $airDropTargeted) { providers in
            DropZones.loadURLs(providers) { shelf.airDrop($0) }
            return true
        }
    }
}

/// While files are dragged to the notch: choose what happens to them by where they're dropped.
struct DropZones: View {
    @ObservedObject var shelf: ShelfManager

    var body: some View {
        HStack(spacing: 10) {
            DropZone(symbol: "tray.and.arrow.down.fill", title: tr("เก็บบนชั้นวาง", "Keep on Shelf"), tint: .white, wide: true,
                     types: [.fileURL, .image]) { providers in
                shelf.add(providers: providers)
                shelf.dropTargeting = false
            }
            DropZone(symbol: "dot.radiowaves.left.and.right", title: "AirDrop", tint: .blue) { providers in
                DropZones.loadURLs(providers) { shelf.airDrop($0) }
            }
            DropZone(symbol: "doc.zipper", title: tr("บีบอัด zip", "Zip"), tint: .orange) { providers in
                DropZones.loadURLs(providers) { shelf.zip($0) }
            }
            DropZone(symbol: "photo.badge.arrow.down", title: tr("ย่อรูป", "Shrink images"), tint: .green) { providers in
                DropZones.loadURLs(providers) { shelf.shrinkImages($0) }
            }
        }
    }

    /// File URLs from a drop, on the main queue.
    static func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { urls.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

private struct DropZone: View {
    let symbol: String
    let title: String
    let tint: Color
    var wide = false
    var types: [UTType] = [.fileURL]
    let onDrop: ([NSItemProvider]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: targeted ? 28 : 24, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(targeted ? Color.white : Color.white.opacity(0.75))
        .frame(maxWidth: wide ? .infinity : 104, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(targeted ? 0.45 : 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(targeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .scaleEffect(targeted ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: targeted)
        .onDrop(of: types, isTargeted: $targeted) { providers in
            onDrop(providers)
            return true
        }
    }
}

/// A chip that drags several files out at once (SwiftUI's own drag carries only one).
/// Files moved elsewhere by the drop leave the shelf, since the shelf only remembers where they were.
struct DragOutHandle: NSViewRepresentable {
    let urls: [URL]
    let label: String
    let onMoved: ([URL]) -> Void

    func makeNSView(context: Context) -> DragOutView {
        let view = DragOutView()
        view.update(urls: urls, label: label, onMoved: onMoved)
        return view
    }

    func updateNSView(_ view: DragOutView, context: Context) {
        view.update(urls: urls, label: label, onMoved: onMoved)
    }

    final class DragOutView: NSView, NSDraggingSource {
        private var urls: [URL] = []
        private var onMoved: ([URL]) -> Void = { _ in }
        private let host = NSHostingView(rootView: AnyView(EmptyView()))

        override init(frame: NSRect) {
            super.init(frame: frame)
            host.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: leadingAnchor), host.trailingAnchor.constraint(equalTo: trailingAnchor),
                host.topAnchor.constraint(equalTo: topAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(urls: [URL], label: String, onMoved: @escaping ([URL]) -> Void) {
            self.urls = urls
            self.onMoved = onMoved
            host.rootView = AnyView(
                Label("\(label) (\(urls.count))", systemImage: "hand.draw.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        // The whole chip takes the mouse, not the SwiftUI label inside it.
        override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

        override func mouseDragged(with event: NSEvent) {
            guard !urls.isEmpty else { return }
            let items: [NSDraggingItem] = urls.enumerated().map { i, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let offset = CGFloat(min(i, 4)) * 6
                item.setDraggingFrame(NSRect(x: offset, y: -offset, width: 48, height: 48), contents: icon)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .move, .generic] : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            guard operation.contains(.move) || operation.contains(.generic) else { return }
            let gone = urls.filter { !FileManager.default.fileExists(atPath: $0.path) }
            if !gone.isEmpty { onMoved(gone) }
        }
    }
}

struct ShelfItemView: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfManager
    @State private var hovering = false

    private var selected: Bool { shelf.selection.contains(item.url) }
    /// Menu actions apply to the whole selection when this item is part of it.
    private var actOn: [URL] { selected ? shelf.selectedOrAll : [item.url] }

    var body: some View {
        VStack(spacing: 4) {
            FileThumbnail(url: item.url)
                .frame(width: 52, height: 52)
                .overlay {
                    if shelf.converting.contains(item.url) {
                        ProgressView().controlSize(.small)
                    }
                }
            Text(item.url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76, height: 26, alignment: .top)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(selected ? 0.16 : hovering ? 0.1 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
        .overlay(alignment: .topLeading) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.8), .black.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onTapGesture { shelf.toggleSelection(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button(tr("เปิด", "Open")) { shelf.open(item) }
            Button(tr("แสดงใน Finder", "Show in Finder")) { shelf.reveal(item) }
            Button(tr("ส่ง AirDrop", "AirDrop")) { shelf.airDrop(actOn) }
            Button(tr("คัดลอกไฟล์", "Copy")) { shelf.copyFiles(actOn) }
            Button(tr("คัดลอกที่อยู่ไฟล์", "Copy Path")) { shelf.copyPaths(actOn) }
            Divider()
            Button(tr("บีบอัดเป็น zip", "Compress to Zip")) { shelf.zip(actOn) }
            if actOn.contains(where: Converter.isImage) {
                Button(tr("ย่อรูป (ส่งแชตง่าย)", "Shrink Image")) { shelf.shrinkImages(actOn) }
            }
            if shelf.imageItems.count >= 2 {
                Button(tr("รวมรูปเป็น PDF", "Combine Images into PDF")) { shelf.combineImagesToPDF() }
            }
            let targets = Converter.targets(for: item.url)
            if !targets.isEmpty {
                Menu(tr("แปลงเป็น", "Convert to")) {
                    ForEach(targets) { target in
                        Button(target.label) { shelf.convert(item, to: target) }
                    }
                }
            }
            if Transcriber.canTranscribe(item.url) {
                Menu(tr("ถอดเสียงเป็นข้อความ", "Transcribe to text")) {
                    ForEach(Transcriber.languages, id: \.id) { language in
                        Button(language.name) { shelf.transcribe(item, language: language.id) }
                    }
                }
            }
            Divider()
            Button(tr("เอาออกจากชั้นวาง", "Remove from Shelf")) { shelf.remove(actOn) }
        }
        .help(item.url.path)
    }
}

/// For pictures, PDFs and videos a Quick Look preview of the file itself; the Finder icon for everything else
/// (a text file's preview is just a blank-looking page at this size).
struct FileThumbnail: View {
    let url: URL
    @State private var preview: NSImage?

    var body: some View {
        Group {
            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            }
        }
        .task(id: url) {
            guard let type = UTType(filenameExtension: url.pathExtension),
                  [.image, .pdf, .movie].contains(where: type.conforms(to:)) else { return }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 52, height: 52),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                preview = rep.nsImage
            }
        }
    }
}
