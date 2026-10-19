import Foundation

// Public Swift reflection avoids treating undocumented ivar offsets or empty
// Objective-C type encodings as proof of a stored reference's representation.
@_cdecl("LensBridgeCopyScriptingReference")
public func copyScriptingReference(_ script: UnsafeMutableRawPointer?, _ field: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let script, let field else { return nil }
    let name=String(cString:field)
    guard name == "layer" || name == "identifier" else { return nil }
    let owner=Unmanaged<AnyObject>.fromOpaque(script).takeUnretainedValue()
    var mirror: Mirror? = Mirror(reflecting:owner)
    while let current=mirror {
        for child in current.children where child.label == name {
            var value=child.value
            let reflected=Mirror(reflecting:value)
            if reflected.displayStyle == .optional {
                guard let wrapped=reflected.children.first else { return nil }
                value=wrapped.value
            }
            // Do not bridge arbitrary Swift values into newly boxed NSObjects.
            guard Mirror(reflecting:value).displayStyle == .class else { return nil }
            let reference=value as AnyObject
            return Unmanaged.passRetained(reference).toOpaque()
        }
        mirror=current.superclassMirror
    }
    return nil
}
