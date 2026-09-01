import AppKit

// Renders the app icon. lockFocus draws at the screen's backing scale, so the
// output is 2048² — the caller downsamples to the required 1024² with `sips`.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
// Warm amber gradient (matches the highlight identity).
let grad = NSGradient(colors: [
    NSColor(red: 1.00, green: 0.76, blue: 0.09, alpha: 1),
    NSColor(red: 1.00, green: 0.44, blue: 0.00, alpha: 1),
])!
grad.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 430, weight: .heavy),
    .foregroundColor: NSColor.white,
    .paragraphStyle: para,
]
let s = "eng" as NSString
let ts = s.size(withAttributes: attrs)
s.draw(at: NSPoint(x: (size - ts.width) / 2, y: (size - ts.height) / 2), withAttributes: attrs)
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
