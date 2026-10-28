import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var shelf: ShelfManager
    @State private var shelfTargeted = false
    @State private var airDropTargeted = false

    var body: some View {
        HStack(spacing: 12) {
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

            VStack(spacing: 8) {
                airDropTarget
                if shelf.imageItems.count >= 2 {
                    Button(tr("รวมรูปเป็น PDF", "Images → PDF")) { shelf.combineImagesToPDF() }
                        .buttonStyle(PillButtonStyle())
                        .help(tr("รวมรูปทั้งหมดบนชั้นวางเป็น PDF ไฟล์เดียว", "Combine every image on the shelf into one PDF"))
                }
                if !shelf.items.isEmpty {
                    Button(tr("ล้าง", "Clear")) { shelf.clear() }
                        .buttonStyle(PillButtonStyle())
                }
            }
            .frame(width: 96)
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
            let group = DispatchGroup()
            var urls: [URL] = []
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { urls.append(url) } }
                    group.leave()
                }
            }
            group.notify(queue: .main) { shelf.airDrop(urls) }
            return true
        }
    }
}

struct ShelfItemView: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfManager
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.1 : 0)))
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
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button(tr("เปิด", "Open")) { shelf.open(item) }
            Button(tr("แสดงใน Finder", "Show in Finder")) { shelf.reveal(item) }
            Button(tr("ส่ง AirDrop", "AirDrop")) { shelf.airDrop([item.url]) }
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
            Button(tr("เอาออกจากชั้นวาง", "Remove from Shelf")) { shelf.remove(item) }
        }
        .help(item.url.path)
    }
}
