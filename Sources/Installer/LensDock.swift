import AppKit
import CryptoKit
import UniformTypeIdentifiers

struct DockError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
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
    guard try word(input, 0, true) == 0xcafebabe else { throw DockError("可执行文件格式不属于已验证版本。") }
    let count = Int(try word(input, 4, true))
    guard count > 0, count <= 16, 8 + count * 20 <= input.count else { throw DockError("无效架构表。") }
    var ranges: [Range<Int>] = []
    for i in 0..<count {
        let base = 8 + i * 20
        if try word(input, base, true) == 0x100000c {
            let start = Int(try word(input, base+8, true)), size = Int(try word(input, base+12, true))
            guard start >= 8 + count * 20, size >= 32, start <= input.count-size else { throw DockError("架构范围无效。") }
            ranges.append(start..<start+size)
        }
    }
    guard ranges.count == 1 else { throw DockError("需要唯一的 Apple 芯片架构。") }
    var image = Data(input[ranges[0]])
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
    func validate(_ source: URL) throws -> [String: Any] {
        #if !arch(arm64)
        throw DockError("预览版仅支持 Apple 芯片 Mac。")
        #else
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { throw DockError("需要 macOS 26 或更新版本；当前只完成 macOS 27.2 实机验证。") }
        let info = try plist(source.appendingPathComponent("Contents/Info.plist"))
        guard info["CFBundleIdentifier"] as? String == compatibility.vendorBundleIdentifier,
              info["CFBundleShortVersionString"] as? String == compatibility.version,
              info["CFBundleVersion"] as? String == compatibility.build,
              info["CFBundleExecutable"] as? String == compatibility.executable else { throw DockError("仅接受已验证的 Pixelmator Pro Creator Studio 4.3（3.0.75）。其他版本暂不能集成。") }
        for (path,expected) in compatibility.fileSHA256 {
            let data = try Data(contentsOf: source.appendingPathComponent(path), options: .mappedIfSafe)
            guard lensDigest(data) == expected else { throw DockError("兼容接口校验不通过：\(URL(fileURLWithPath:path).lastPathComponent)。应用可能已更新，请等待适配。") }
        }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
        _ = try patchedExecutable(Data(contentsOf: source.appendingPathComponent("Contents/MacOS/"+compatibility.executable)))
        return info
        #endif
    }
    func install(_ source: URL, applicationsDirectory: URL? = nil, progress: @escaping (String)->Void) throws -> URL {
        progress("检查本机 Pixelmator 与兼容接口…")
        var info = try validate(source)
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
        for (path,expected) in compatibility.fileSHA256 {
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
        let note=label("需要 Pixelmator 4.3（3.0.75）与 Apple 芯片 Mac。仅本机建立独立宿主；正式覆盖范围和稳定性仍在验证。",NSRect(x:32,y:134,width:510,height:54),12);note.textColor = .secondaryLabelColor
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
