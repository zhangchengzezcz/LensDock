import Darwin
import Foundation

// Pixelmator 5 exports the Codable value but no longer exports its Objective-C
// wrapper. Open the real host type so Swift handles its ownership and coding.
func hostEffectsType() -> (any Codable.Type)? {
    guard let metadata = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "$s12PTFoundation9PTEffectsVN") else { return nil }
    return unsafeBitCast(metadata, to: Any.Type.self) as? any Codable.Type
}

private func withDecodedEffects<T: Codable>(
    _ type: T.Type, _ data: Data, _ consumer: (UnsafeRawPointer) -> Void
) -> Data? {
    guard MemoryLayout<T>.size == 16, MemoryLayout<T>.stride == 16,
          MemoryLayout<T>.alignment == 8,
          let effects = try? JSONDecoder().decode(type, from: data),
          let canonical = try? JSONEncoder().encode(effects) else { return nil }
    withUnsafePointer(to: effects) { consumer(UnsafeRawPointer($0)) }
    return canonical
}

private func encodeOwnedEffects<T: Codable>(_ type: T.Type, _ storage: UnsafeMutableRawPointer) -> Data? {
    guard MemoryLayout<T>.size == 16, MemoryLayout<T>.stride == 16,
          MemoryLayout<T>.alignment == 8 else { return nil }
    // The native getter supplied one owned value. Moving it into Swift
    // consumes that ownership even if encoding fails.
    let value = storage.assumingMemoryBound(to: type).move()
    return try? JSONEncoder().encode(value)
}

@_cdecl("LensBridgeEncodeOwnedEffects")
public func lensBridgeEncodeOwnedEffects(_ storage: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let storage, let type = hostEffectsType(),
          let data = encodeOwnedEffects(type, storage) else { return nil }
    return Unmanaged.passRetained(data as NSData).toOpaque()
}

@_cdecl("LensBridgeDecodeEffects")
public func lensBridgeDecodeEffects(
    _ data: UnsafeRawPointer?,
    _ context: UnsafeMutableRawPointer?,
    _ consumer: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> Void)?
) -> UnsafeMutableRawPointer? {
    guard let data, let type = hostEffectsType() else { return nil }
    let source = Unmanaged<NSData>.fromOpaque(data).takeUnretainedValue() as Data
    guard let canonical = withDecodedEffects(type, source, { consumer?(context, $0) }) else { return nil }
    return Unmanaged.passRetained(canonical as NSData).toOpaque()
}
