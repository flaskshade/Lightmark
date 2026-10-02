import AppKit
import CoreText
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("assets/InstrumentSerif-Regular.ttf") as CFURL, .process, nil)
let image = NSImage(size: NSSize(width:1200,height:630))
image.lockFocus()
NSColor(calibratedWhite:0.98,alpha:1).setFill()
NSRect(x:0,y:0,width:1200,height:630).fill()
let glow = NSGradient(starting:NSColor(calibratedRed:237/255,green:225/255,blue:154/255,alpha:0.23),ending:NSColor(calibratedWhite:0.98,alpha:0))!
glow.draw(in:NSBezierPath(ovalIn:NSRect(x:335,y:180,width:530,height:450)),relativeCenterPosition:NSPoint(x:0,y:0))
NSImage(contentsOf:root.appendingPathComponent("assets/lightmark.png"))!.draw(in:NSRect(x:518,y:385,width:164,height:164))
func text(_ value:String,_ y:CGFloat,_ font:NSFont,_ color:NSColor) {
 let style=NSMutableParagraphStyle();style.alignment = .center
 (value as NSString).draw(in:NSRect(x:70,y:y,width:1060,height:110),withAttributes:[.font:font,.foregroundColor:color,.paragraphStyle:style,.kern:-1])
}
text("Lightmark",255,NSFont(name:"InstrumentSerif-Regular",size:96) ?? NSFont.systemFont(ofSize:96),NSColor(calibratedWhite:0.13,alpha:1))
text("A native Markdown utility for macOS.",172,NSFont.systemFont(ofSize:29,weight:.light),NSColor(calibratedWhite:0.4,alpha:1))
text("100% free. Forever.",70,NSFont.systemFont(ofSize:20),NSColor(calibratedWhite:0.5,alpha:1))
image.unlockFocus()
let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("assets/social-preview.png"))
