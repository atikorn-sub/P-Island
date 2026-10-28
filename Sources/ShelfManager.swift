import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}

/// Files parked in the notch. Stores references (paths), not copies.
final class ShelfManager: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var converting: Set<URL> = []
    /// Items picked with a click, for acting on several at once.
    @Published var selection: Set<URL> = []
    /// A file drag is on its way to the notch: the shelf shows its drop zones.
    @Published var dropTargeting = false

    var onAdded: ((Int) -> Void)?

    private let defaultsKey = "shelf.paths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(ShelfItem.init)
    }

    func add(_ urls: [URL]) {
        let fresh = urls.filter { url in !items.contains { $0.url == url } }
        guard !fresh.isEmpty else { return }
        items.append(contentsOf: fresh.map(ShelfItem.init))
        save()
        onAdded?(fresh.count)
    }

    /// Accepts file URLs, or raw images (e.g. dragged from a browser) which get saved to disk first.
    @discardableResult
    func add(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        func collect(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        collect(url)
                    } else if let url = item as? URL {
                        collect(url)
                    }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                group.enter()
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage, let url = Self.saveImage(image) { collect(url) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { self.add(urls) }
        return !providers.isEmpty
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
        selection.remove(item.url)
        save()
    }

    func remove(_ urls: [URL]) {
        items.removeAll { urls.contains($0.url) }
        selection.subtract(urls)
        save()
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
        save()
    }

    func toggleSelection(_ item: ShelfItem) {
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
    }

    /// The picked items in shelf order, or everything when nothing is picked.
    var selectedOrAll: [URL] {
        let picked = items.map(\.url).filter { selection.contains($0) }
        return picked.isEmpty ? items.map(\.url) : picked
    }

    /// Puts the files on the clipboard, ready to paste into Finder, Mail, LINE and so on.
    func copyFiles(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        onMessage?(tr("คัดลอกแล้ว", "Copied"), urls.count == 1 ? urls[0].lastPathComponent : tr("\(urls.count) ไฟล์", "\(urls.count) files"), true)
    }

    func copyPaths(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        onMessage?(tr("คัดลอกที่อยู่ไฟล์แล้ว", "Path copied"), urls.count == 1 ? urls[0].path : tr("\(urls.count) ไฟล์", "\(urls.count) files"), true)
    }

    /// One .zip of the files, saved beside the first one and put on the shelf.
    func zip(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        urls.forEach { converting.insert($0) }
        Converter.zip(urls) { [weak self] output in
            DispatchQueue.main.async {
                guard let self else { return }
                urls.forEach { self.converting.remove($0) }
                if let output {
                    self.add([output])
                    self.onMessage?(tr("บีบอัดเป็น zip แล้ว", "Zipped"), output.lastPathComponent, true)
                } else {
                    self.onMessage?(tr("บีบอัดไม่สำเร็จ", "Couldn't zip"), "", false)
                }
            }
        }
    }

    /// Smaller JPEG copies of the images (longest side 2048 px), for sending in chats and email.
    func shrinkImages(_ urls: [URL]) {
        let images = urls.filter(Converter.isImage)
        guard !images.isEmpty else { return NSSound.beep() }
        images.forEach { converting.insert($0) }
        DispatchQueue.global(qos: .userInitiated).async {
            let results = images.map { ($0, Converter.shrinkImage($0)) }
            DispatchQueue.main.async {
                results.forEach { self.converting.remove($0.0) }
                let outputs = results.compactMap(\.1)
                self.add(outputs)
                let saved = Swift.zip(images, outputs).reduce(Int64(0)) { $0 + Converter.size($1.0) - Converter.size($1.1) }
                self.onMessage?(tr("ย่อรูปแล้ว \(outputs.count) รูป", "Shrank \(outputs.count) image\(outputs.count == 1 ? "" : "s")"),
                                saved > 0 ? tr("ประหยัดไป \(Converter.format(saved))", "Saved \(Converter.format(saved))") : "", !outputs.isEmpty)
            }
        }
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        if service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        } else {
            NSSound.beep()
        }
    }

    /// Shows a short message in the notch (title, subtitle, success).
    var onMessage: ((String, String, Bool) -> Void)?

    func transcribe(_ item: ShelfItem, language: String) {
        converting.insert(item.url)
        Transcriber.transcribe(item.url, language: language) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.converting.remove(item.url)
                switch result {
                case .success(let url):
                    self.add([url])
                    self.onMessage?(tr("ถอดเสียงเสร็จแล้ว", "Transcript ready"), url.lastPathComponent, true)
                case .failure(let error):
                    self.onMessage?(tr("ถอดเสียงไม่สำเร็จ", "Couldn't transcribe"), error.message, false)
                }
            }
        }
    }

    var imageItems: [ShelfItem] {
        items.filter { UTType(filenameExtension: $0.url.pathExtension)?.conforms(to: .image) == true }
    }

    func combineImagesToPDF() {
        Converter.combineImages(imageItems.map(\.url)) { [weak self] output in
            DispatchQueue.main.async {
                if let output { self?.add([output]) } else { NSSound.beep() }
            }
        }
    }

    func convert(_ item: ShelfItem, to target: ConversionTarget) {
        converting.insert(item.url)
        Converter.convert(item.url, to: target) { [weak self] output in
            DispatchQueue.main.async {
                guard let self else { return }
                self.converting.remove(item.url)
                if let output {
                    self.add([output])
                } else {
                    NSSound.beep()
                }
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: defaultsKey)
    }

    private static func saveImage(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Islet/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = dir.appendingPathComponent("Image \(formatter.string(from: Date())).png")
        return (try? png.write(to: url)) != nil ? url : nil
    }
}

// MARK: - Converter

enum ConversionTarget: String, CaseIterable, Identifiable {
    case png, jpeg, heic, tiff, pdf, mp4, mov, m4a

    var id: String { rawValue }

    var label: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .mp4: return "MP4"
        case .mov: return "MOV"
        case .m4a: return tr("M4A (เฉพาะเสียง)", "M4A (audio only)")
        case .pdf: return "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        default: return rawValue
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .mp4: return .mpeg4Movie
        case .mov: return .quickTimeMovie
        case .m4a: return .mpeg4Audio
        case .pdf: return .pdf
        }
    }
}

enum Converter {
    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    static func size(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// A single file or folder zips as "<name>.zip"; several go into "Archive.zip", each at the top level.
    static func zip(_ urls: [URL], completion: @escaping (URL?) -> Void) {
        guard let first = urls.first else { return completion(nil) }
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var source = first
            var staging: URL?
            if urls.count > 1 {
                // Gather them in one folder (APFS clones, so no extra space) and zip that folder's contents.
                let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent("Archive", isDirectory: true)
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                for url in urls { try? fm.copyItem(at: url, to: dir.appendingPathComponent(url.lastPathComponent)) }
                source = dir
                staging = dir.deletingLastPathComponent()
            }
            let name = urls.count > 1 ? "Archive" : first.lastPathComponent
            let output = outputURL(for: first.deletingLastPathComponent().appendingPathComponent(name), ext: "zip")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            // --keepParent for one item keeps its own name inside; for several, the files sit at the top.
            // No resource forks or extended attributes, so no "__MACOSX" clutter when it's opened on Windows.
            task.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noacl"] + (urls.count > 1 ? [] : ["--keepParent"]) + [source.path, output.path]
            try? task.run()
            task.waitUntilExit()
            if let staging { try? fm.removeItem(at: staging) }
            completion(task.terminationStatus == 0 && fm.fileExists(atPath: output.path) ? output : nil)
        }
    }

    /// A JPEG copy no longer than 2048 px on its longest side, turned upright, named "<name> (small).jpg".
    static func shrinkImage(_ source: URL) -> URL? {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options) else { return nil }
        let base = source.deletingPathExtension().lastPathComponent + tr(" (ย่อ)", " (small)")
        let output = outputURL(for: source.deletingLastPathComponent().appendingPathComponent(base), ext: "jpg")
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? output : nil
    }

    static func targets(for url: URL) -> [ConversionTarget] {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return [] }
        let options: [ConversionTarget]
        if type.conforms(to: .image) {
            options = [.png, .jpeg, .heic, .tiff, .pdf]
        } else if type.conforms(to: .movie) {
            options = [.mp4, .mov, .m4a]
        } else if type.conforms(to: .audio) {
            options = [.m4a]
        } else if isDocument(url, type: type) {
            options = [.pdf]
        } else {
            options = []
        }
        return options.filter { !type.conforms(to: $0.utType) }
    }

    /// Text documents AppKit can read: Word, RTF, OpenDocument, HTML and plain text.
    private static func isDocument(_ url: URL, type: UTType) -> Bool {
        if ["docx", "doc", "odt", "rtfd"].contains(url.pathExtension.lowercased()) { return true }
        return [.rtf, .html, .plainText].contains { type.conforms(to: $0) }
    }

    /// Puts several images into one PDF, one image per page, saved next to the first image.
    static func combineImages(_ urls: [URL], completion: @escaping (URL?) -> Void) {
        guard let first = urls.first else { return completion(nil) }
        let output = outputURL(for: first.deletingLastPathComponent().appendingPathComponent("Images.pdf"), ext: "pdf")
        DispatchQueue.global(qos: .userInitiated).async {
            let doc = PDFDocument()
            for url in urls {
                if let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
                    doc.insert(page, at: doc.pageCount)
                }
            }
            completion(doc.pageCount > 0 && doc.write(to: output) ? output : nil)
        }
    }

    static func convert(_ source: URL, to target: ConversionTarget, completion: @escaping (URL?) -> Void) {
        let output = outputURL(for: source, ext: target.fileExtension)
        switch target {
        case .png, .jpeg, .heic, .tiff:
            DispatchQueue.global(qos: .userInitiated).async {
                completion(convertImage(source, to: output, type: target.utType) ? output : nil)
            }
        case .pdf:
            if UTType(filenameExtension: source.pathExtension)?.conforms(to: .image) == true {
                combineImages([source]) { combined in
                    guard let combined else { return completion(nil) }
                    try? FileManager.default.moveItem(at: combined, to: output)
                    completion(FileManager.default.fileExists(atPath: output.path) ? output : nil)
                }
            } else {
                // Text layout and printing must happen on the main thread.
                DispatchQueue.main.async {
                    completion(documentToPDF(source, to: output) ? output : nil)
                }
            }
        case .mp4, .mov, .m4a:
            let asset = AVURLAsset(url: source)
            let preset = target == .m4a ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return completion(nil) }
            session.outputURL = output
            session.outputFileType = target == .mp4 ? .mp4 : target == .mov ? .mov : .m4a
            session.exportAsynchronously {
                completion(session.status == .completed ? output : nil)
            }
        }
    }

    private static func convertImage(_ source: URL, to output: URL, type: UTType) -> Bool {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else { return false }
        let props = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImageFromSource(dest, src, 0, props)
        return CGImageDestinationFinalize(dest)
    }

    /// Lays the document out on A4 pages and prints it straight to a PDF file, without any dialog.
    private static func documentToPDF(_ source: URL, to output: URL) -> Bool {
        guard let text = try? NSAttributedString(url: source, options: [:], documentAttributes: nil) else { return false }
        let info = NSPrintInfo(dictionary: [.jobSavingURL: output])
        info.jobDisposition = .save
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 56
        info.bottomMargin = 56
        info.leftMargin = 56
        info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.textStorage?.setAttributedString(text)
        if let layout = view.layoutManager, let container = view.textContainer {
            layout.ensureLayout(for: container)
            view.frame.size.height = layout.usedRect(for: container).height + 10
        }
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        return operation.run() && FileManager.default.fileExists(atPath: output.path)
    }

    /// Next to the original when possible, otherwise in Downloads. Never overwrites.
    private static func outputURL(for source: URL, ext: String) -> URL {
        var dir = source.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: dir.path) {
            dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
