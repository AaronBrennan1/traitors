// Rewrites PNGs without an alpha channel. App Store Connect turns away screenshots that have one.
//   swift Tools/flatten-png.swift a.png b.png ...
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { print("could not read \(path)"); exit(1) }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let flat = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { print("could not write \(path)"); exit(1) }
    CGImageDestinationAddImage(destination, flat, nil)
    guard CGImageDestinationFinalize(destination) else { print("could not write \(path)"); exit(1) }
}
