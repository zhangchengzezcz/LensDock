import Foundation

// Opaque reference declarations only. No vendor object is constructed or cast
// through these types; their instances are the host's retained native references.
private final class LensOpaqueEngine: NSObject {}
private final class LensOpaqueIdentifier: NSObject {}
private extension LensOpaqueEngine {
    @_silgen_name("$s9PXMEngine6EngineC20exportRawLayerSource15layerIdentifier2toy12PTFoundation16PTHashableStringC_10Foundation3URLVtKF")
    func exportOriginalRAW(layerIdentifier: LensOpaqueIdentifier, to: URL) throws
    @_silgen_name("$s9PXMEngine6EngineC26registerHistoryTransactionyySSF")
    func registerLensHistory(_ actionName: String)
}

@_cdecl("LensBridgeRegisterLensHistory")
public func registerLensHistory(_ engine: UnsafeMutableRawPointer?) -> Bool {
    guard let engine else { return false }
    Unmanaged<LensOpaqueEngine>.fromOpaque(engine).takeUnretainedValue().registerLensHistory("镜头矫正")
    return true
}

@_cdecl("LensBridgeExportOriginalRAW")
public func exportOriginalRAW(_ engine: UnsafeMutableRawPointer?, _ identifier: UnsafeMutableRawPointer?, _ destination: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let engine, let identifier, let destination else {
        return Unmanaged.passRetained(NSError(domain: "LensBridgeLive", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少原生 RAW 数据引用。"])).toOpaque()
    }
    let owner = Unmanaged<LensOpaqueEngine>.fromOpaque(engine).takeUnretainedValue()
    let layerID = Unmanaged<LensOpaqueIdentifier>.fromOpaque(identifier).takeUnretainedValue()
    let url = Unmanaged<NSURL>.fromOpaque(destination).takeUnretainedValue()
    do {
        try owner.exportOriginalRAW(layerIdentifier: layerID, to: url as URL)
        return nil
    } catch {
        return Unmanaged.passRetained(error as NSError).toOpaque()
    }
}
