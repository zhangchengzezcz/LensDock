import AppKit
import CryptoKit
import UniformTypeIdentifiers

struct DockError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
struct SourceVariant: Codable {
    let id: String
    let fileSHA256: [String: String]
}
struct Compatibility: Codable {
    let schema: Int
    let vendorBundleIdentifier: String
    let version: String
    let build: String
    let executable: String
    let minimumOS: String
    let architecture: String
    let fileSHA256: [String: String]
    let sourceVariants: [SourceVariant]?
    let arm64CodeSHA256: [String: String]?
    let codeFingerprintAlgorithm: String?
}
let hostID = "local.lensdock.pixelmator"
let hostName = "Pixelmator LensDock Preview.app"
let fm = FileManager.default
let previewVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
func installedHostIsCurrent(_ info: [String: Any], version: String, expectedHash: String, actualHash: String) -> Bool {
    info["CFBundleIdentifier"] as? String == hostID &&
    info["LensDockPreviewVersion"] as? String == version &&
    info["LensDockPayloadSHA256"] as? String == expectedHash &&
    !expectedHash.isEmpty && !actualHash.isEmpty && info["LensDockNativeModuleSHA256"] as? String == actualHash
}
func lensDigest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func machNumber(_ data: Data, _ offset: Int, _ width: Int = 4, _ big: Bool = false) throws -> UInt64 {
    guard offset >= 0, width > 0, width <= 8, width <= data.count, offset <= data.count-width else { throw DockError("Mach-O 指纹数据越界。") }
    var value: UInt64 = 0
    for i in 0..<width { value |= UInt64(data[offset+i]) << ((big ? width-1-i : i)*8) }
    return value
}
func arm64Image(_ input: Data) throws -> Data {
    func number(_ data: Data, _ offset: Int, _ width: Int = 4, _ big: Bool = false) throws -> UInt64 { try machNumber(data,offset,width,big) }
    var image = input
    let magic = try number(input,0,4,true)
    if magic == 0xcafebabe || magic == 0xcafebabf {
        let count = Int(try number(input,4,4,true)), stride = magic == 0xcafebabf ? 32 : 20
        guard count > 0, count <= 16, 8+count*stride <= input.count else { throw DockError("无效通用架构表。") }
        var selected: Range<Int>?, ranges: [Range<Int>] = []
        for i in 0..<count {
            let p = 8+i*stride, wide = stride == 32
            let start = try number(input,p+8,wide ? 8 : 4,true)
            let size = try number(input,p+(wide ? 16 : 12),wide ? 8 : 4,true)
            let align = try number(input,p+(wide ? 24 : 16),4,true)
            guard align <= 31, start >= UInt64(8+count*stride), size >= 32,
                  start <= UInt64(input.count), size <= UInt64(input.count)-start,
                  start % (UInt64(1)<<align) == 0 else { throw DockError("架构范围或对齐无效。") }
            let range = Int(start)..<Int(start+size)
            guard ranges.allSatisfy({ !$0.overlaps(range) }) else { throw DockError("架构范围重叠。") }
            ranges.append(range)
            if try number(input,p,4,true) == 0x100000c {
                guard selected == nil else { throw DockError("重复 arm64 架构。") }
                selected = range
            }
        }
        guard let selected else { throw DockError("缺少 arm64 架构。") }
        image = Data(input[selected])
    }
    guard try number(image,0) == 0xfeedfacf, try number(image,4) == 0x100000c else { throw DockError("无效 arm64 指纹输入。") }
    return image
}
// v1 binds every pre-signature byte except signature-dependent lengths.
func arm64CodeDigest(_ input: Data) throws -> String {
    func number(_ data: Data, _ offset: Int, _ width: Int = 4, _ big: Bool = false) throws -> UInt64 { try machNumber(data,offset,width,big) }
    var image = try arm64Image(input)
    let count = Int(try number(image,16)), size = Int(try number(image,20))
    guard count > 0, count <= 4096, size >= count*8, size <= image.count-32 else { throw DockError("无效加载表。") }
    var p = 32, signature: (Int,Int,Int)?, link: (Int,Int,Int,Int)?
    for _ in 0..<count {
        let command = try number(image,p), length = Int(try number(image,p+4))
        guard length >= 8, length % 8 == 0, p <= 32+size-length else { throw DockError("加载表越界。") }
        if command == 0x2c {
            guard length == 24, try number(image,p+16) == 0 else { throw DockError("不能集成加密版本。") }
        }
        if command == 0x1d {
            guard length == 16, signature == nil else { throw DockError("无效签名命令。") }
            signature = (p,Int(try number(image,p+8)),Int(try number(image,p+12)))
        }
        if command == 0x19 {
            guard length >= 72 else { throw DockError("无效段命令。") }
            let name = Data(image[p+8..<p+24])
            if name == Data(Array("__LINKEDIT".utf8)+Array(repeating:0,count:6)) {
                guard link == nil, length == 72, try number(image,p+64) == 0 else { throw DockError("无效 LINKEDIT。") }
                let offset = try number(image,p+40,8), bytes = try number(image,p+48,8), vm = try number(image,p+32,8)
                guard offset <= UInt64(image.count), bytes <= UInt64(image.count)-offset,
                      vm == (bytes+16383) & ~UInt64(16383) else { throw DockError("LINKEDIT 签名尺寸无效。") }
                link = (p,Int(offset),Int(bytes),Int(vm))
            }
        }
        p += length
    }
    guard p == 32+size, let (sigCommand,offset,bytes) = signature, let (linkCommand,start,linkBytes,_) = link,
          offset >= p, offset >= start, bytes > 0, offset <= image.count,
          bytes == image.count-offset, start+linkBytes == image.count else { throw DockError("签名必须位于最终 LINKEDIT 尾部。") }
    image = Data(image[..<offset])
    func put(_ value: UInt64, _ position: Int, _ width: Int) {
        for i in 0..<width { image[position+i] = UInt8(truncatingIfNeeded:value >> (i*8)) }
    }
    put(0,sigCommand+12,4)
    put(UInt64(offset-start),linkCommand+48,8)
    put((UInt64(offset-start)+16383) & ~UInt64(16383),linkCommand+32,8)
    return lensDigest(image)
}
func run(_ executable: String, _ arguments: [String]) throws -> Data {
    let task = Process(), pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
    task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
    try task.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
    guard task.terminationStatus == 0 else { throw DockError("步骤失败：\(URL(fileURLWithPath: executable).lastPathComponent)（\(task.terminationStatus)）。未替换已安装应用。") }
    return output
}
func plist(_ url: URL) throws -> [String: Any] {
    guard let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else { throw DockError("应用信息无效。") }
    return value
}
// Reject malformed, encrypted, non-arm64 or already modified executable inputs.
// Only the verified local copy receives a new LC_LOAD_DYLIB command.
func patchedExecutable(_ input: Data) throws -> Data {
    func word(_ data: Data, _ offset: Int, _ big: Bool = false) throws -> UInt32 {
        guard offset >= 0, offset <= data.count - 4 else { throw DockError("Mach-O 数据越界。") }
        let bytes = [UInt32](data[offset..<offset+4].map { UInt32($0) })
        return big ? bytes[0]<<24 | bytes[1]<<16 | bytes[2]<<8 | bytes[3] : bytes[0] | bytes[1]<<8 | bytes[2]<<16 | bytes[3]<<24
    }
    var image = try arm64Image(input)
    guard try word(image, 0) == 0xfeedfacf, try word(image, 4) == 0x100000c else { throw DockError("无效的 arm64 Mach-O。") }
    let commands = Int(try word(image, 16)), size = Int(try word(image, 20))
    guard commands <= 4096, size >= 8*commands, size <= image.count-32 else { throw DockError("无效加载命令。") }
    var pos = 32, firstSection = image.count
    for _ in 0..<commands {
        let command = try word(image, pos), length = Int(try word(image, pos+4))
        guard length >= 8, length % 8 == 0, pos <= 32+size-length else { throw DockError("加载命令越界。") }
        if command == 0x2c {
            guard length >= 24, try word(image, pos+16) == 0 else { throw DockError("加密版本不能集成；没有修改原应用。") }
        }
        if command == 0x19 {
            guard length >= 72 else { throw DockError("无效段表。") }
            let sections = Int(try word(image, pos+64))
            guard sections <= (length-72)/80 else { throw DockError("段表越界。") }
            for i in 0..<sections {
                let offset = Int(try word(image, pos+72+i*80+48))
                if offset > 0 { firstSection = min(firstSection, offset) }
            }
        }
        pos += length
    }
    guard pos == 32+size else { throw DockError("加载表大小不一致。") }
    let path = Data("@executable_path/../Frameworks/LensPanel.dylib\0".utf8)
    let length = (24+path.count+7) & ~7
    guard pos+length <= firstSection, pos+length <= image.count, image[pos..<pos+length].allSatisfy({ $0 == 0 }) else { throw DockError("没有足够的空白头部空间。") }
    func put(_ value: UInt32, _ offset: Int) {
        for i in 0..<4 { image[offset+i] = UInt8(truncatingIfNeeded: value >> (i*8)) }
    }
    for (offset,value) in [(0,UInt32(0xc)),(4,UInt32(length)),(8,UInt32(24)),(12,UInt32(0)),(16,UInt32(0x10000)),(20,UInt32(0x10000))] { put(value,pos+offset) }
    image.replaceSubrange(pos+24..<pos+24+path.count, with:path)
    put(UInt32(commands+1),16); put(UInt32(size+length),20)
    return image
}
struct Installer {
    let resources: URL
    let compatibility: Compatibility
    init(resources: URL) throws {
        self.resources = resources
        compatibility = try JSONDecoder().decode(Compatibility.self, from: Data(contentsOf: resources.appendingPathComponent("Pixelmator-4.3.json")))
    }
    func verifiedSourceHashes(_ source: URL) throws -> [String: String] {
        let protectedPaths: Set<String> = [
            "Contents/MacOS/"+compatibility.executable,
            "Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",
            "Contents/Frameworks/PXMEngine.framework/Versions/A/PXMEngine",
            "Contents/Frameworks/PXMKit.framework/Versions/A/PXMKit"
        ]
        let candidates = [compatibility.fileSHA256] + (compatibility.sourceVariants ?? []).map(\.fileSHA256)
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard candidates.allSatisfy({ candidate in
            Set(candidate.keys) == protectedPaths && candidate.values.allSatisfy {
                $0.count == 64 && $0.unicodeScalars.allSatisfy { hexadecimal.contains($0) }
            }
        }) else { throw DockError("兼容记录不完整，已停止安装。") }
        var actual: [String: String] = [:]
        for path in protectedPaths {
            actual[path] = lensDigest(try Data(contentsOf: source.appendingPathComponent(path), options: .mappedIfSafe))
        }
        // Match a complete, independently verified source variant. Do not mix
        // individually allowed files from different variants during validation.
        if !candidates.contains(actual) {
            guard compatibility.codeFingerprintAlgorithm == "arm64-code-v1",
                  let expected = compatibility.arm64CodeSHA256, Set(expected.keys) == protectedPaths,
                  expected.values.allSatisfy({ $0.count == 64 && $0.unicodeScalars.allSatisfy { hexadecimal.contains($0) } }) else {
                throw DockError("四个兼容接口文件不属于同一套已验证版本。应用可能已更新，请等待适配。")
            }
            for path in protectedPaths {
                guard try arm64CodeDigest(Data(contentsOf:source.appendingPathComponent(path),options:.mappedIfSafe)) == expected[path] else {
                    throw DockError("应用代码或兼容接口发生变化，请等待适配。")
                }
            }
        }
        return actual
    }
    func validatedSource(_ source: URL) throws -> (info: [String: Any], hashes: [String: String]) {
        #if !arch(arm64)
        throw DockError("预览版仅支持 Apple 芯片 Mac。")
        #else
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { throw DockError("需要 macOS 26 或更新版本；当前只完成 macOS 27.2 实机验证。") }
        let info = try plist(source.appendingPathComponent("Contents/Info.plist"))
        guard info["CFBundleIdentifier"] as? String == compatibility.vendorBundleIdentifier,
              info["CFBundleShortVersionString"] as? String == compatibility.version,
              info["CFBundleVersion"] as? String == compatibility.build,
              info["CFBundleExecutable"] as? String == compatibility.executable else { throw DockError("仅接受已验证的 Pixelmator Pro Creator Studio 4.3（3.0.75）。其他版本暂不能集成。") }
        let hashes = try verifiedSourceHashes(source)
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
        _ = try patchedExecutable(Data(contentsOf: source.appendingPathComponent("Contents/MacOS/"+compatibility.executable)))
        return (info,hashes)
        #endif
    }
    func validate(_ source: URL) throws -> [String: Any] { try validatedSource(source).info }
    func install(_ source: URL, applicationsDirectory: URL? = nil, progress: @escaping (String)->Void) throws -> URL {
        progress("检查本机 Pixelmator 与兼容接口…")
        let verified = try validatedSource(source)
        var info = verified.info
        let sourceHashes = verified.hashes
        let applications = applicationsDirectory ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications",isDirectory:true)
        let destination = applications.appendingPathComponent(hostName,isDirectory:true)
        guard !fm.fileExists(atPath: destination.path) else { throw DockError("预览宿主已存在。可先打开；重新安装前请将旧宿主移到废纸篓。已有文件不会被覆盖。") }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: hostID).isEmpty else { throw DockError("请先关闭 LensDock 的 Pixelmator 窗口。") }
        try fm.createDirectory(at:applications,withIntermediateDirectories:true)
        let staging = applications.appendingPathComponent(".LensDock-\(UUID().uuidString).app",isDirectory:true)
        defer { if fm.fileExists(atPath:staging.path) { try? fm.removeItem(at:staging) } }
        progress("从你本机的应用建立独立预览宿主…")
        _ = try run("/usr/bin/ditto",[source.path,staging.path])
        // Verify the copied critical bytes too; refuse source updates during copy.
        for (path,expected) in sourceHashes {
            guard lensDigest(try Data(contentsOf:staging.appendingPathComponent(path),options:.mappedIfSafe)) == expected else { throw DockError("复制期间应用内容变化，已停止安装。") }
        }
        let executable = staging.appendingPathComponent("Contents/MacOS/"+compatibility.executable)
        try patchedExecutable(Data(contentsOf:executable)).write(to:executable)
        let payload = resources.appendingPathComponent("Payload",isDirectory:true)
        for (from,to) in [("LensPanel.dylib","Contents/Frameworks/LensPanel.dylib"),("LensLiveSource.dylib","Contents/Frameworks/LensLiveSource.dylib"),("Lib","Contents/Frameworks/LensBridge"),("LensBridge","Contents/Resources/LensBridge"),("native-effects-template.json","Contents/Resources/native-effects-template.json")] {
            try fm.copyItem(at:payload.appendingPathComponent(from),to:staging.appendingPathComponent(to))
        }
        info["CFBundleIdentifier"] = hostID; info["CFBundleName"] = "Pixelmator LensDock Preview"; info["CFBundleDisplayName"] = "Pixelmator LensDock Preview"
        info["LensDockPreviewVersion"] = previewVersion; info["LensDockPayloadSHA256"] = lensDigest(try Data(contentsOf:payload.appendingPathComponent("LensPanel.dylib")))
        info["LensDockSourceFileSHA256"] = sourceHashes
        let infoURL = staging.appendingPathComponent("Contents/Info.plist")
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:infoURL)
        var entitlements = try PropertyListSerialization.propertyList(from:run("/usr/bin/codesign",["-d","--entitlements","-","--xml",source.path]),format:nil) as? [String:Any] ?? [:]
        entitlements["com.apple.application-identifier"] = hostID
        entitlements.removeValue(forKey:"com.apple.security.application-groups")
        let entURL = applications.appendingPathComponent(".LensDock-\(UUID().uuidString).plist")
        defer { try? fm.removeItem(at:entURL) }
        try PropertyListSerialization.data(fromPropertyList:entitlements,format:.xml,options:0).write(to:entURL)
        progress("签名并验证预览宿主…")
        _ = try run("/usr/bin/codesign",["--force","--deep","--sign","-","--entitlements",entURL.path,staging.path])
        // Deep signing can change the module signature bytes. Record the signed
        // module separately from the release payload, then reseal only the host.
        info["LensDockNativeModuleSHA256"] = lensDigest(try Data(contentsOf:staging.appendingPathComponent("Contents/Frameworks/LensPanel.dylib")))
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:infoURL)
        _ = try run("/usr/bin/codesign",["--force","--sign","-","--entitlements",entURL.path,staging.path])
        _ = try run("/usr/bin/codesign",["--verify","--deep","--strict",staging.path])
        try fm.moveItem(at:staging,to:destination)
        progress("安装完成。打开后选择 RAW 图层，再进入“镜头矫正”。")
        return destination
    }
}
final class DockApp: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var status: NSTextField!
    var sourceLabel: NSTextField!
    var installButton: NSButton!
    var chooseButton: NSButton!
    var openButton: NSButton!
    var spinner: NSProgressIndicator!
    var source = URL(fileURLWithPath:"/Applications/Pixelmator Pro Creator Studio.app")
    var installed: URL?
    var busy = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle:"退出 LensDock",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        item.submenu=appMenu; menu.addItem(item); NSApp.mainMenu=menu
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:470),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="LensDock · 镜头坞"; window.isReleasedWhenClosed=false
        let root=window.contentView!
        func label(_ text:String,_ rect:NSRect,_ size:CGFloat,_ weight:NSFont.Weight = .regular)->NSTextField {
            let v=NSTextField(wrappingLabelWithString:text);v.frame=rect;v.font=NSFont.systemFont(ofSize:size,weight:weight);root.addSubview(v);return v
        }
        _ = label("LensDock",NSRect(x:30,y:398,width:510,height:42),32,.semibold)
        let subtitle=label("镜头坞 · 保留 RAW 的 Pixelmator 镜头矫正",NSRect(x:32,y:366,width:510,height:25),15);subtitle.textColor = .secondaryLabelColor
        _ = label("预览版 \(previewVersion)",NSRect(x:32,y:322,width:480,height:24),13,.semibold)
        let explanation=label("畸变、色差、去暗角分别调整。原生支持时自动跳过补充畸变与色差，额外去暗角默认关闭。",NSRect(x:32,y:264,width:510,height:52),14);explanation.textColor = .secondaryLabelColor
        _ = label("本机 Pixelmator",NSRect(x:32,y:230,width:390,height:22),13,.medium)
        sourceLabel=label(source.lastPathComponent,NSRect(x:32,y:200,width:385,height:24),12);sourceLabel.lineBreakMode = .byTruncatingMiddle;sourceLabel.setAccessibilityLabel("已选择的 Pixelmator 应用")
        chooseButton=NSButton(title:"选择应用…",target:self,action:#selector(choose));chooseButton.frame=NSRect(x:428,y:199,width:120,height:30);root.addSubview(chooseButton)
        let note=label("需要 macOS 26 或更新版本、Apple 芯片与 Pixelmator 4.3（3.0.75）。当前实测 macOS 27.2，其他系统版本仍待实测。",NSRect(x:32,y:134,width:510,height:54),12);note.textColor = .secondaryLabelColor
        status=label("选择本机应用后安装。首次完成后通过 LensDock 打开。",NSRect(x:54,y:88,width:490,height:42),12);status.isSelectable=true
        spinner=NSProgressIndicator(frame:NSRect(x:30,y:107,width:16,height:16));spinner.style = .spinning;spinner.isIndeterminate=true;spinner.isDisplayedWhenStopped=false;root.addSubview(spinner)
        installButton=NSButton(title:"安装预览宿主",target:self,action:#selector(install));installButton.frame=NSRect(x:32,y:30,width:190,height:34);installButton.bezelStyle = .rounded;root.addSubview(installButton)
        openButton=NSButton(title:"打开 Pixelmator",target:self,action:#selector(openHost));openButton.frame=NSRect(x:350,y:30,width:198,height:34);openButton.bezelStyle = .rounded;openButton.isEnabled=false;root.addSubview(openButton)
        let existing=fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/"+hostName)
        if let info=try? plist(existing.appendingPathComponent("Contents/Info.plist")),info["CFBundleIdentifier"] as? String == hostID {
            installed=existing;openButton.isEnabled=true;installButton.isEnabled=false
            let expected=(try? Data(contentsOf:Bundle.main.resourceURL!.appendingPathComponent("Payload/LensPanel.dylib"))).map { lensDigest($0) } ?? ""
            let actual=(try? Data(contentsOf:existing.appendingPathComponent("Contents/Frameworks/LensPanel.dylib"))).map { lensDigest($0) } ?? ""
            let current=installedHostIsCurrent(info,version:previewVersion,expectedHash:expected,actualHash:actual)
            status.stringValue=current ? "已安装当前预览宿主，可直接打开。" : "检测到旧版或不同构建。请先退出旧宿主并将它移到废纸篓，再重新打开 LensDock 安装新版；PXD 与原片会保留。"
        }
        window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { !busy }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply { busy ? .terminateCancel : .terminateNow }
    @objc func choose() {
        let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.canChooseFiles=true;panel.allowedContentTypes=[.applicationBundle];panel.prompt="选择 Pixelmator"
        if panel.runModal() == .OK,let url=panel.url { source=url;sourceLabel.stringValue=url.lastPathComponent;status.stringValue="安装前会校验版本与兼容接口。" }
    }
    @objc func install() {
        guard !busy,let resources=Bundle.main.resourceURL else {return}
        busy=true;chooseButton.isEnabled=false;installButton.isEnabled=false;openButton.isEnabled=false;spinner.startAnimation(nil)
        let original=source
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let installer=try Installer(resources:resources)
                let destination=try installer.install(original){ message in DispatchQueue.main.async {self.status.stringValue=message} }
                DispatchQueue.main.async {self.installed=destination;self.busy=false;self.spinner.stopAnimation(nil);self.openButton.isEnabled=true;self.chooseButton.isEnabled=true}
            } catch {
                DispatchQueue.main.async {self.busy=false;self.spinner.stopAnimation(nil);self.chooseButton.isEnabled=true;self.installButton.isEnabled=true;self.status.stringValue=error.localizedDescription}
            }
        }
    }
    @objc func openHost() {
        guard let installed else {return}
        let configuration=NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at:installed,configuration:configuration){_,error in if let error { DispatchQueue.main.async {self.status.stringValue=error.localizedDescription} } }
    }
}
// Read-only compatibility/parser checks do not launch a UI or modify an app.
if CommandLine.arguments.count == 3,CommandLine.arguments[1] == "--verify-source" {
    do {
        let installer=try Installer(resources:Bundle.main.resourceURL!)
        _ = try installer.validate(URL(fileURLWithPath:CommandLine.arguments[2]))
        for invalid in [Data(),Data(repeating:0,count:64)] { do { _ = try patchedExecutable(invalid);throw DockError("无效格式被接受。") } catch let error as DockError { if error.message == "无效格式被接受。" {throw error} } }
        print("Version, ABI hashes, signature, arm64 parser and malformed-input rejection passed.")
    } catch { fputs(error.localizedDescription+"\n",stderr);exit(1) }
} else if CommandLine.arguments == [CommandLine.arguments[0], "--verify-installation-state"] {
    let info: [String: Any]=["CFBundleIdentifier":hostID,"LensDockPreviewVersion":"0.2.0","LensDockPayloadSHA256":"current-payload","LensDockNativeModuleSHA256":"signed-module"]
    func accepts(_ value: [String: Any], _ actual: String = "signed-module", _ wanted: String = "current-payload") -> Bool { installedHostIsCurrent(value,version:"0.2.0",expectedHash:wanted,actualHash:actual) }
    guard accepts(info) else {exit(1)}
    for (key,value) in [("LensDockPreviewVersion","0.1.0"),("CFBundleIdentifier","com.apple.pixelmator"),("LensDockPayloadSHA256","old-payload"),("LensDockNativeModuleSHA256","wrong-signed-module")] {
        var changed=info;changed[key]=value;guard !accepts(changed) else {exit(2)}
    }
    var missing=info;missing.removeValue(forKey:"LensDockNativeModuleSHA256")
    guard !accepts(missing),!accepts(info,"changed-module"),!accepts(info,"","") else {exit(3)}
    print("Current host accepted; old version, wrong identity, missing/stale stamp, changed module and missing payload rejected.")
} else {
    let application=NSApplication.shared, delegate=DockApp(); application.delegate=delegate;application.run()
}
