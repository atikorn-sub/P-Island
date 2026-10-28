import AppKit
import SwiftUI

/// Where a file dragged onto the shelf can go.
enum DropZoneKind: CaseIterable {
    case shelf, airDrop, zip, shrink
}

/// The panel's content. It takes file drags for the whole panel itself instead of leaving them to
/// SwiftUI's per-view drop targets, which only catch a drop right on top of them and can miss views
/// that appear mid-drag. Every point of the panel belongs to the nearest drop zone.
final class NotchHostingView: NSHostingView<NotchRootView> {
    private var state: NotchState?

    convenience init(state: NotchState) {
        self.init(rootView: NotchRootView(state: state))
        self.state = state
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init(rootView: NotchRootView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        state?.shelf.hoveredZone = nil
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        state?.shelf.hoveredZone != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let shelf = state?.shelf, let zone = shelf.hoveredZone else { return false }
        let pb = sender.draggingPasteboard
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let images = urls.isEmpty ? (pb.readObjects(forClasses: [NSImage.self]) as? [NSImage] ?? []) : []
        shelf.hoveredZone = nil
        shelf.dropTargeting = false
        // Let the drag finish first; AirDrop in particular opens its own window.
        DispatchQueue.main.async {
            switch zone {
            case .shelf:
                if urls.isEmpty { shelf.addImages(images) } else { shelf.add(urls) }
            case .airDrop: shelf.airDrop(urls)
            case .zip: shelf.zip(urls)
            case .shrink: shelf.shrinkImages(urls)
            }
        }
        return !urls.isEmpty || !images.isEmpty
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        state?.shelf.hoveredZone = nil
    }

    /// Picks the zone under (or nearest to) the pointer; the shelf view lights it up.
    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let state, state.isOpen else { return [] }
        if state.tab != .shelf { state.tab = .shelf }
        if !state.shelf.dropTargeting { state.shelf.dropTargeting = true }
        let local = convert(sender.draggingLocation, from: nil)
        // SwiftUI's frames are measured from the top.
        let point = CGPoint(x: local.x, y: bounds.height - local.y)
        let hasFiles = sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        // Until the zones have been laid out (the first moment of a drag), everything means "keep it".
        let zone = Self.nearest(to: point, in: state.shelf.zoneFrames, shelfOnly: !hasFiles) ?? .shelf
        if state.shelf.hoveredZone != zone { state.shelf.hoveredZone = zone }
        return .copy
    }

    /// The zone containing the point, else the closest one. A picture dragged from a browser (no file)
    /// can only be kept on the shelf.
    private static func nearest(to p: CGPoint, in frames: [DropZoneKind: CGRect], shelfOnly: Bool) -> DropZoneKind? {
        let candidates = frames.filter { !shelfOnly || $0.key == .shelf }
        if let hit = candidates.first(where: { $0.value.contains(p) }) { return hit.key }
        return candidates.min { distance(p, $0.value) < distance(p, $1.value) }?.key
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}
