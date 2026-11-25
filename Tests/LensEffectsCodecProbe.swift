import Foundation

private func initializeValue<T: Decodable>(_ type: T.Type, data: Data, storage: UnsafeMutableRawPointer) -> Bool {
    guard MemoryLayout<T>.size == 16, let value = try? JSONDecoder().decode(type, from: data) else { return false }
    storage.bindMemory(to: type, capacity: 1).initialize(to: value)
    return true
}

private func encodeBorrowedValue<T: Encodable>(_ type: T.Type, storage: UnsafeRawPointer) -> Data? {
    guard MemoryLayout<T>.size == 16 else { return nil }
    return try? JSONEncoder().encode(storage.assumingMemoryBound(to: type).pointee)
}

@_cdecl("LensTestDecodeOwnedEffects")
public func lensTestDecodeOwnedEffects(_ source: UnsafeRawPointer, _ storage: UnsafeMutableRawPointer) -> Bool {
    guard let type = hostEffectsType() else { return false }
    let data = Unmanaged<NSData>.fromOpaque(source).takeUnretainedValue() as Data
    return initializeValue(type, data: data, storage: storage)
}

@_cdecl("LensTestEncodeBorrowedEffects")
public func lensTestEncodeBorrowedEffects(_ storage: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    guard let type = hostEffectsType(), let data = encodeBorrowedValue(type, storage: storage) else { return nil }
    return Unmanaged.passRetained(data as NSData).toOpaque()
}
