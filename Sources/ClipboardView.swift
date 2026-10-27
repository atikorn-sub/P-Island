import SwiftUI

struct ClipboardView: View {
    @ObservedObject var clipboard: ClipboardManager
    @State private var query = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                    TextField("ค้นหาในคลิปบอร์ด", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                if !clipboard.items.isEmpty {
                    Button("ล้าง") { clipboard.clear() }.buttonStyle(PillButtonStyle())
                }
            }
            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 24))
                    Text(clipboard.items.isEmpty ? "คัดลอกอะไรก็ได้ แล้วจะมาอยู่ที่นี่" : "ไม่พบรายการที่ค้นหา")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { item in
                            ClipRow(item: item, clipboard: clipboard)
                        }
                    }
                }
            }
        }
    }

    private var filtered: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return clipboard.items }
        return clipboard.items.filter { item in
            switch item.content {
            case .text(let s): return s.localizedCaseInsensitiveContains(q)
            case .files(let urls): return urls.contains { $0.lastPathComponent.localizedCaseInsensitiveContains(q) }
            case .image: return false
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    @ObservedObject var clipboard: ClipboardManager
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            preview
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if clipboard.lastCopiedID == item.id {
                Label("คัดลอกแล้ว", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else if hovering {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.1 : 0.04)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { clipboard.copy(item) }
        .onDrag { clipboard.dragProvider(for: item) }
        .contextMenu {
            Button("คัดลอก") { clipboard.copy(item) }
            Button("ลบ") { clipboard.remove(item) }
        }
        .help("คลิกเพื่อคัดลอกอีกครั้ง")
    }

    @ViewBuilder private var preview: some View {
        switch item.content {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        case .image(let url):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        case .files(let urls):
            Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path)).resizable()
        }
    }

    private var title: String {
        switch item.content {
        case .text(let s):
            return s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        case .image: return "รูปภาพ"
        case .files(let urls):
            return urls.count == 1 ? urls[0].lastPathComponent : "\(urls[0].lastPathComponent) +\(urls.count - 1)"
        }
    }

    private var subtitle: String {
        let time = item.date.formatted(.dateTime.hour().minute().locale(.thai))
        return [item.sourceApp, time].compactMap { $0 }.joined(separator: " · ")
    }
}
