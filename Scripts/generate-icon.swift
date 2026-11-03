import AppKit

// A vector-drawn magnifying glass, rendered at every macOS icon resolution.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
            pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.65, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
        NSColor.white.setStroke()
        let handle = NSBezierPath()
        handle.lineWidth = 76
        handle.lineCapStyle = .round
        handle.move(to: NSPoint(x: 593, y: 431))
        handle.line(to: NSPoint(x: 754, y: 270))
        handle.stroke()
        let lens = NSBezierPath(ovalIn: NSRect(x: 266, y: 406, width: 376, height: 376))
        lens.lineWidth = 66
        lens.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
        try png.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

// Package PNG representations directly into the standard ICNS container.
var chunks = Data()
func bigEndianBytes(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
for (type, name) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
                     ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
                     ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
                     ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
                     ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
                     ("ic14", "icon_256x256@2x.png")] {
    let png = try Data(contentsOf: output.appendingPathComponent(name))
    chunks.append(Data(type.utf8))
    chunks.append(bigEndianBytes(png.count + 8))
    chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndianBytes(chunks.count + 8))
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
