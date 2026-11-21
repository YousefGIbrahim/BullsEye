import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("No context") }
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r / 255, g / 255, b / 255, 1])!
}
context.setFillColor(color(16, 59, 51))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setStrokeColor(color(246, 244, 236))
context.setLineWidth(76)
context.strokeEllipse(in: CGRect(x: 230, y: 230, width: 564, height: 564))
context.setFillColor(color(231, 197, 104))
context.fillEllipse(in: CGRect(x: 412, y: 412, width: 200, height: 200))
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
guard let image = context.makeImage(),
      let output = CGImageDestinationCreateWithURL(folder.appendingPathComponent("Bullseye.png") as CFURL,
                                                    UTType.png.identifier as CFString, 1, nil) else { fatalError("No destination") }
CGImageDestinationAddImage(output, image, nil)
guard CGImageDestinationFinalize(output) else { fatalError("Write failed") }
try Data("""
{"images":[{"filename":"Bullseye.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
""".utf8).write(to: folder.appendingPathComponent("Contents.json"))

// Legacy icon files keep the installed icon configured when Xcode's target-setting
// bridge cannot set ASSETCATALOG_COMPILER_APPICON_NAME. The catalog remains the source.
let appFolder = folder.deletingLastPathComponent().deletingLastPathComponent()
for (name, pixels) in [("BullseyeIcon60@2x", 120), ("BullseyeIcon60@3x", 180),
                       ("BullseyeIcon76@2x", 152), ("BullseyeIcon83.5@2x", 167)] {
    guard let scaled = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                bytesPerRow: 0, space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Scale context") }
    scaled.interpolationQuality = .high
    scaled.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    guard let result = scaled.makeImage(),
          let destination = CGImageDestinationCreateWithURL(appFolder.appendingPathComponent(name + ".png") as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) else { fatalError("Icon destination") }
    CGImageDestinationAddImage(destination, result, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Icon write") }
}
