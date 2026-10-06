import AppKit

let size = NSSize(width: 720, height: 460)
let image = NSImage(size: size)
image.lockFocus()
let canvas = NSRect(origin: .zero, size: size)
NSGradient(colors: [NSColor(red: 0.07, green: 0.08, blue: 0.16, alpha: 1),
                    NSColor(red: 0.16, green: 0.10, blue: 0.29, alpha: 1)])!.draw(in: canvas, angle: 25)

func label(_ value: String, top: CGFloat, size fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (value as NSString).draw(in: NSRect(x: 30, y: 460 - top - fontSize * 1.6, width: 660, height: fontSize * 1.6),
                            withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                                             .foregroundColor: color, .paragraphStyle: style])
}
label("VideoVault", top: 38, size: 34, weight: .bold, color: .white)
label("Your videos. Ready when you are.", top: 90, size: 15, weight: .regular,
      color: NSColor(white: 0.8, alpha: 1))
for x: CGFloat in [190, 530] {
    let circle = NSBezierPath(ovalIn: NSRect(x: x - 69, y: 460 - 218 - 69, width: 138, height: 138))
    NSColor(white: 1, alpha: 0.06).setFill()
    circle.fill()
    NSColor(white: 1, alpha: 0.12).setStroke()
    circle.lineWidth = 1
    circle.stroke()
}
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 316, y: 242))
arrow.line(to: NSPoint(x: 403, y: 242))
arrow.move(to: NSPoint(x: 390, y: 255))
arrow.line(to: NSPoint(x: 403, y: 242))
arrow.line(to: NSPoint(x: 390, y: 229))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(red: 0.64, green: 0.64, blue: 1, alpha: 1).setStroke()
arrow.stroke()
label("Drag VideoVault to Applications", top: 326, size: 21, weight: .semibold, color: .white)
label("Then open VideoVault from Applications and eject this disk.", top: 363, size: 13,
      weight: .regular, color: NSColor(white: 0.75, alpha: 1))
label("macOS 13+    ·    Intel & Apple Silicon    ·    Automatic updates", top: 413, size: 11,
      weight: .medium, color: NSColor(white: 0.6, alpha: 1))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
