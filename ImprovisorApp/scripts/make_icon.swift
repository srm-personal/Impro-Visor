#!/usr/bin/env swift
// Generates the Leadsheet Studio app icon (1024×1024 PNG plus every macOS size)
// with CoreGraphics: a rounded macOS tile, a staff, an eighth note and a chord
// symbol. Original artwork — nothing borrowed from Impro-Visor.
//
// Usage: swift scripts/make_icon.swift [output-appiconset-dir]

import AppKit

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "App/LeadsheetStudio/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: CGFloat) -> CGImage {
    let s = size
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let u = s / 1024 // unit

    // macOS tile: inset rounded rect.
    let tile = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185 * u, cornerHeight: 185 * u, transform: nil)
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let colors = [CGColor(red: 0.10, green: 0.16, blue: 0.36, alpha: 1), CGColor(red: 0.16, green: 0.42, blue: 0.62, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    // Soft highlight.
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.06))
    ctx.fillEllipse(in: CGRect(x: tile.minX - 200 * u, y: tile.midY, width: tile.width + 400 * u, height: tile.height))

    // Staff lines.
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.82))
    ctx.setLineWidth(14 * u)
    let staffTop = 400 * u, gap = 62 * u
    for i in 0..<5 {
        let y = staffTop + CGFloat(i) * gap
        ctx.move(to: CGPoint(x: tile.minX + 70 * u, y: y)); ctx.addLine(to: CGPoint(x: tile.maxX - 70 * u, y: y))
    }
    ctx.strokePath()

    // Eighth note: head on the second space, stem up, flag.
    let cream = CGColor(red: 1.0, green: 0.93, blue: 0.72, alpha: 1)
    ctx.setFillColor(cream); ctx.setStrokeColor(cream)
    let head = CGPoint(x: 600 * u, y: staffTop + 1.5 * gap)
    ctx.saveGState()
    ctx.translateBy(x: head.x, y: head.y); ctx.rotate(by: 0.42)
    ctx.fillEllipse(in: CGRect(x: -62 * u, y: -44 * u, width: 124 * u, height: 88 * u))
    ctx.restoreGState()
    ctx.setLineWidth(22 * u); ctx.setLineCap(.round)
    let stemX = head.x + 52 * u, stemTop = head.y + 300 * u
    ctx.move(to: CGPoint(x: stemX, y: head.y)); ctx.addLine(to: CGPoint(x: stemX, y: stemTop)); ctx.strokePath()
    ctx.setLineWidth(34 * u)
    ctx.move(to: CGPoint(x: stemX, y: stemTop))
    ctx.addCurve(to: CGPoint(x: stemX + 150 * u, y: stemTop - 200 * u),
                 control1: CGPoint(x: stemX + 40 * u, y: stemTop - 40 * u),
                 control2: CGPoint(x: stemX + 170 * u, y: stemTop - 80 * u))
    ctx.strokePath()

    // Chord symbol.
    let text = "F7" as NSString
    let font = NSFont.systemFont(ofSize: 215 * u, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: cream)!]
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let textSize = text.size(withAttributes: attrs)
    _ = textSize
    text.draw(at: CGPoint(x: tile.minX + 110 * u, y: staffTop + 4 * gap + 28 * u), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (pt, scale) in sizes {
    let px = pt * scale
    let name = "icon_\(pt)x\(pt)@\(scale)x.png"
    writePNG(render(size: CGFloat(px)), to: outDir.appendingPathComponent(name))
    images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outDir.path)")
