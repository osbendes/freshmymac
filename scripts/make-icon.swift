#!/usr/bin/env swift
// Uygulama ikonunu üretir: swift scripts/make-icon.swift  →  Resources/AppIcon.icns
import AppKit

let root = URL(filePath: FileManager.default.currentDirectoryPath)
let iconset = root.appending(path: "build/AppIcon.iconset")
let output = root.appending(path: "Resources/AppIcon.icns")

/// Merkezi (x, y), dış yarıçapı r olan dört köşeli parıltı; kenarlar merkeze doğru içbükey.
func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, pinch: CGFloat = 0.12) -> NSBezierPath {
    let tips = [NSPoint(x: x, y: y + r), NSPoint(x: x + r, y: y), NSPoint(x: x, y: y - r), NSPoint(x: x - r, y: y)]
    let path = NSBezierPath()
    path.move(to: tips[0])
    for i in 0..<4 {
        let a = tips[i], b = tips[(i + 1) % 4]
        let mid = NSPoint(x: x + (a.x - x + b.x - x) * pinch, y: y + (a.y - y + b.y - y) * pinch)
        path.curve(to: b, controlPoint1: mid, controlPoint2: mid)
    }
    path.close()
    path.lineJoinStyle = .round
    return path
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // PhoneDrop ile aynı ızgara, sarı gradyan ve mürekkep rengi; motif parıltı.
    let s = CGFloat(px) / 1024
    let rect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.86, blue: 0.33, alpha: 1),
               ending: NSColor(srgbRed: 1.0, green: 0.78, blue: 0.10, alpha: 1))!.draw(in: shape, angle: -90)

    let ink = NSColor(srgbRed: 0.17, green: 0.165, blue: 0.157, alpha: 1)
    ink.setFill()
    ink.setStroke()
    let big = sparkle(560 * s, 450 * s, 255 * s)
    big.lineWidth = 28 * s
    big.stroke()
    sparkle(305 * s, 720 * s, 95 * s).fill()
    sparkle(780 * s, 790 * s, 58 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Hazır: Resources/AppIcon.icns" : "iconutil başarısız")
