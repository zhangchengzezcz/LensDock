import Foundation
import ImageIO
import CoreGraphics
import CryptoKit

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.bitsPerComponent == 16, let space = image.colorSpace,
      space.model == .rgb, image.width > 0, image.height > 0,
      image.width * image.height <= 120_000_000 else { fatalError("Requires a 16-bit RGB image") }
let width = image.width, height = image.height
var pixels = [UInt16](repeating: 0, count: width * height * 4)
var transparent = 0, nonopaque = 0, edge = 0, minimum: UInt16 = 65535
let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
pixels.withUnsafeMutableBytes { buffer in
    guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
        bitsPerComponent: 16, bytesPerRow: width * 8, space: space, bitmapInfo: info)
        else { fatalError("Cannot create 16-bit audit bitmap") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let data = buffer.bindMemory(to: UInt16.self)
    for y in 0..<height { for x in 0..<width {
        let alpha = data[(y*width+x)*4+3]
        minimum = min(minimum, alpha)
        if alpha < 65535 {
            nonopaque += 1
            if x < 32 || y < 32 || x >= width-32 || y >= height-32 { edge += 1 }
        }
        if alpha == 0 { transparent += 1 }
    }}
}
let icc = space.copyICCData() as Data? ?? Data()
let report: [String: Any] = [
    "scope": "Actual host-exported PNG decoded in its embedded RGB color space at 16 bits; alpha audit, not optical accuracy",
    "filename": url.lastPathComponent, "width": width, "height": height,
    "bitsPerComponent": image.bitsPerComponent, "colorSpace": space.name as String? ?? "unknown",
    "fileBytes": try Data(contentsOf: url).count,
    "fileSHA256": SHA256.hash(data: try Data(contentsOf: url)).map { String(format:"%02x",$0) }.joined(),
    "iccSHA256": SHA256.hash(data: icc).map { String(format:"%02x",$0) }.joined(),
    "minimumAlpha16Bit": Int(minimum), "nonopaquePixels": nonopaque,
    "transparentPixels": transparent, "outer32PixelBandNonopaquePixels": edge,
    "allPixelsOpaque": nonopaque == 0,
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print(String(decoding:data,as:UTF8.self))
