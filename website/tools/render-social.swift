import AppKit
import CoreText
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("assets/InstrumentSerif-Regular.ttf") as CFURL, .process, nil)
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1200,pixelsHigh:630,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
NSColor.white.setFill()
NSRect(x:0,y:0,width:1200,height:630).fill()
let warm = NSColor(calibratedRed:237/255,green:225/255,blue:154/255,alpha:1)
let glow = NSGradient(colorsAndLocations:(warm.withAlphaComponent(0.30),0),(warm.withAlphaComponent(0.16),0.32),(warm.withAlphaComponent(0.05),0.55),(warm.withAlphaComponent(0),0.85))!
glow.draw(in:NSBezierPath(ovalIn:NSRect(x:405,y:265,width:390,height:340)),relativeCenterPosition:.zero)
let icon = NSImage(contentsOf:root.appendingPathComponent("assets/lightmark.png"))!
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedRed:60/255,green:48/255,blue:24/255,alpha:0.09)
shadow.shadowBlurRadius = 18
shadow.shadowOffset = NSSize(width:0,height:-12)
shadow.set()
icon.draw(in:NSRect(x:510,y:325,width:180,height:180))
NSGraphicsContext.restoreGraphicsState()
// Render the website's actual font and mask its graphite gradient into the letters.
let titleFont = NSFont(name:"InstrumentSerif-Regular",size:112)!
let attributes:[NSAttributedString.Key:Any] = [.font:titleFont,.foregroundColor:NSColor.white,.kern:-2.8]
let title = "Lightmark" as NSString
let titleSize = title.size(withAttributes:attributes)
let titleImage = NSImage(size:titleSize)
titleImage.lockFocus()
title.draw(at:.zero,withAttributes:attributes)
NSGraphicsContext.current!.compositingOperation = .sourceIn
NSGradient(colors:[NSColor(calibratedWhite:0.13,alpha:1),NSColor(calibratedWhite:0.19,alpha:1),NSColor(calibratedWhite:0.27,alpha:1)])!.draw(in:NSRect(origin:.zero,size:titleSize),angle:-90)
titleImage.unlockFocus()
titleImage.draw(in:NSRect(x:(1200-titleSize.width)/2,y:175,width:titleSize.width,height:titleSize.height))
let subtitle = "A native Markdown utility for macOS." as NSString
let subtitleAttributes:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:25,weight:.light),.foregroundColor:NSColor(calibratedRed:98/255,green:98/255,blue:103/255,alpha:1),.kern:-0.625]
let subtitleSize = subtitle.size(withAttributes:subtitleAttributes)
subtitle.draw(at:NSPoint(x:(1200-subtitleSize.width)/2,y:117),withAttributes:subtitleAttributes)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("assets/social-preview.png"))
