// Maakt donkere (zwarte) pixels wit, zodat het logo zichtbaar is op de zwarte Touch Bar.
// Gebruik: whiten in.png out.png
import AppKit
let a = CommandLine.arguments
let src = NSImage(contentsOfFile: a[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let w = src.width, h = src.height
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
for i in stride(from: 0, to: w * h * 4, by: 4) {
    let alpha = px[i + 3]
    guard alpha > 0 else { continue }
    // premultiplied: donker als de kleur ver onder alpha ligt
    let maxc = max(px[i], px[i + 1], px[i + 2])
    if Double(maxc) < Double(alpha) * 0.35 { px[i] = alpha; px[i + 1] = alpha; px[i + 2] = alpha }
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
