import AppKit
import CoreText
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("assets/InstrumentSerif-Regular.ttf") as CFURL, .process, nil)
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1200,pixelsHigh:630,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
NSColor(srgbRed:29/255,green:29/255,blue:31/255,alpha:1).setFill()
NSRect(x:0,y:0,width:1200,height:630).fill()
// Gaussian falloff gives the stronger aura no visible boundary.
let auraBitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1200,pixelsHigh:630,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
let pixels = auraBitmap.bitmapData!
for y in 0..<630 {
    for x in 0..<1200 {
        let dx = Double(x-600)/125, dy = Double(y-238)/110
        let alpha = 0.40 * exp(-0.5*(dx*dx+dy*dy))
        let offset = y*auraBitmap.bytesPerRow+x*4
        pixels[offset] = UInt8(237*alpha)
        pixels[offset+1] = UInt8(225*alpha)
        pixels[offset+2] = UInt8(154*alpha)
        pixels[offset+3] = UInt8(255*alpha)
    }
}
let aura = NSImage(size:NSSize(width:1200,height:630))
aura.addRepresentation(auraBitmap)
aura.draw(in:NSRect(x:0,y:0,width:1200,height:630))
let icon = NSImage(contentsOf:root.appendingPathComponent("assets/lightmark.png"))!
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedRed:60/255,green:48/255,blue:24/255,alpha:0.09)
shadow.shadowBlurRadius = 18
shadow.shadowOffset = NSSize(width:0,height:-12)
shadow.set()
icon.draw(in:NSRect(x:510,y:302,width:180,height:180))
NSGraphicsContext.restoreGraphicsState()
// Match the website's dark-mode white-to-muted serif title.
let titleFont = NSFont(name:"InstrumentSerif-Regular",size:112)!
let attributes:[NSAttributedString.Key:Any] = [.font:titleFont,.foregroundColor:NSColor.white,.kern:-2.8]
let title = "Lightmark" as NSString
let titleSize = title.size(withAttributes:attributes)
let titleImage = NSImage(size:titleSize)
titleImage.lockFocus()
title.draw(at:.zero,withAttributes:attributes)
NSGraphicsContext.current!.compositingOperation = .sourceIn
NSGradient(colors:[NSColor.white,NSColor.white,NSColor.white.withAlphaComponent(0.55)])!.draw(in:NSRect(origin:.zero,size:titleSize),angle:-90)
titleImage.unlockFocus()
titleImage.draw(in:NSRect(x:(1200-titleSize.width)/2,y:137,width:titleSize.width,height:titleSize.height))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("assets/social-preview.png"))
