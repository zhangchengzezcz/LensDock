// Developer observation tool. Never linked into LensDock or used to enable a profile.
import Foundation
import CoreImage
import ImageIO
import Vision

enum ObservationError: Error { case arguments, image, size, result }
func load(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ObservationError.image }
    return image
}
func register(_ target: CGImage, _ moving: CGImage) throws -> [String: Any] {
    guard target.width == moving.width, target.height == moving.height else { throw ObservationError.size }
    let translation = VNTranslationalImageRegistrationRequest(targetedCGImage: target, options: [:])
    let homography = VNHomographicImageRegistrationRequest(targetedCGImage: target, options: [:])
    try VNImageRequestHandler(cgImage: moving, options: [:]).perform([translation, homography])
    guard let t = (translation.results?.first as? VNImageTranslationAlignmentObservation)?.alignmentTransform,
          let m = (homography.results?.first as? VNImageHomographicAlignmentObservation)?.warpTransform
          else { throw ObservationError.result }
    return ["translationAffine": [t.a, t.b, t.c, t.d, t.tx, t.ty],
            "homographyColumns": [[m.columns.0.x, m.columns.0.y, m.columns.0.z],
                                  [m.columns.1.x, m.columns.1.y, m.columns.1.z],
                                  [m.columns.2.x, m.columns.2.y, m.columns.2.z]]]
}
func run() throws -> [String: Any] {
    let args = CommandLine.arguments
    guard args.count >= 4 else { throw ObservationError.arguments }
    if args[1] == "render", args.count == 5, let scale = Double(args[4]), scale > 0, scale <= 1 {
        guard let raw = CIRAWFilter(imageURL: URL(fileURLWithPath: args[2])),
              let image = raw.outputImage else { throw ObservationError.image }
        let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.cacheIntermediates: false])
        try context.writePNGRepresentation(of: resized, to: URL(fileURLWithPath: args[3]), format: .RGBA8,
                                          colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:])
        return ["nativePixelSize": [raw.nativeSize.width, raw.nativeSize.height],
                "outputExtent": [image.extent.minX, image.extent.minY, image.extent.width, image.extent.height],
                "orientation": raw.orientation.rawValue,
                "nativeLensCorrectionSupported": raw.isLensCorrectionSupported,
                "nativeLensCorrectionEnabled": raw.isLensCorrectionEnabled,
                "observationScale": scale, "observationPixels": [resized.extent.width, resized.extent.height]]
    }
    guard args[1] == "register", args.count == 5, ["full", "tiles"].contains(args[4]) else { throw ObservationError.arguments }
    let target = try load(args[2]), moving = try load(args[3])
    var observations: [[String: Any]] = []
    var full = try register(target, moving)
    full["region"] = [0, 0, target.width, target.height]
    full["name"] = "full"
    observations.append(full)
    if args[4] == "tiles" {
        let width = target.width / 2, height = target.height / 2
        for row in 0..<3 { for column in 0..<3 {
            let rect = CGRect(x: column * (target.width - width) / 2,
                              y: row * (target.height - height) / 2, width: width, height: height)
            guard let a = target.cropping(to: rect), let b = moving.cropping(to: rect) else { throw ObservationError.image }
            var item = try register(a, b)
            item["name"] = "tile-\(row)-\(column)"
            item["region"] = [rect.minX, rect.minY, rect.width, rect.height]
            observations.append(item)
        } }
    }
    return ["targetPixels": [target.width, target.height], "observations": observations]
}
do {
    let report = try run()
    print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
} catch {
    // No absolute image paths or metadata are printed on failure.
    fputs("Decoder-frame observation failed: \(error)\n", stderr)
    exit(1)
}
