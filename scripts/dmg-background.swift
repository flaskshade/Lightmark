import AppKit
let image = NSImage(size: NSSize(width: 560, height: 340))
image.lockFocus()
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: 560, height: 340).fill()
func label(_ text: String, _ rect: NSRect, _ size: CGFloat, _ color: NSColor) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .regular), .foregroundColor: color, .paragraphStyle: style])
}
label("→", NSRect(x: 240, y: 168, width: 80, height: 45), 34, .systemGray)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
