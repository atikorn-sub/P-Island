// Builds png/logo-options.png: the three concepts side by side, large and at Dock size.
// usage: swift make-sheet.swift  (run from the Design folder)
import AppKit

let concepts: [(file: String, label: String)] = [
    ("png/logo-a-island-p.svg.png", "A · เกาะรูปตัว P"),
    ("png/logo-b-notch-glow.svg.png", "B · รอยบากเรืองแสง"),
    ("png/logo-c-pebble.svg.png", "C · แคปซูลมินิมอล"),
]

let big: CGFloat = 400, small: CGFloat = 64, gap: CGFloat = 40
let width = big * 3 + gap * 4
let height = gap + big + 56 + small + gap
let sheet = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor(white: 0.15, alpha: 1),
        .paragraphStyle: style,
    ]
    for (i, concept) in concepts.enumerated() {
        guard let image = NSImage(contentsOfFile: concept.file) else { continue }
        let x = gap + CGFloat(i) * (big + gap)
        image.draw(in: NSRect(x: x, y: gap, width: big, height: big))
        concept.label.draw(in: NSRect(x: x, y: gap + big + 8, width: big, height: 32), withAttributes: attrs)
        image.draw(in: NSRect(x: x + (big - small) / 2, y: gap + big + 50, width: small, height: small))
    }
    return true
}
let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "png/logo-options.png"))
print("wrote png/logo-options.png")
