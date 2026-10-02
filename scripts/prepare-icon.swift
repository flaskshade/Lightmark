import AppKit

// macOS icons use an 824-point artwork area within a 1024-point canvas.
// Preserve the supplied pixels and transparency while adding the standard inset.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: source),
      let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let context = CGContext(data: nil, width: 1024, height: 1024,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Could not load Lightmark icon")
}
context.interpolationQuality = .high
context.draw(bitmap, in: CGRect(x: 100, y: 100, width: 824, height: 824))
guard let output = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else {
    fatalError("Could not encode Lightmark icon")
}
try png.write(to: destination)
