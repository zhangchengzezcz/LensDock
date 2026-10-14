import Foundation
import AppKit
var stale=false
let bookmark=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
let resolved=try URL(resolvingBookmarkData:bookmark,options:[.withoutUI,.withoutMounting],relativeTo:nil,bookmarkDataIsStale:&stale)
let volume=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true).resolvingSymlinksInPath()
let path=resolved.resolvingSymlinksInPath().path
if !path.hasPrefix(volume.path+"/.background/") || !FileManager.default.fileExists(atPath:path) {fputs("Background did not resolve inside remounted image.\n",stderr);exit(1)}
print("Finder bookmark resolves to the embedded picture after remount: \(resolved.lastPathComponent)")

let image=NSImage(contentsOf:resolved)!
guard image.size == NSSize(width:760,height:480), image.representations.contains(where:{$0 is NSPDFImageRep}) else {fputs("Vector background or logical size is incorrect.\n",stderr);exit(1)}
print("Vector background verified: 760x480 points; resolution independent")
