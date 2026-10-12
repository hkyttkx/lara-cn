//
//  AzTuTPermissions.swift — 权限层适配
//  3105 原本用 MCM(bad_query) + KernelExploit 拿容器访问;
//  这里换成 lara 的 vfs, 所以把 3105 的权限符号做成适配/占位。
//
import Foundation

// MARK: - KernelExploit 适配 (接到 lara 的 vfs)
enum KernelExploit {
    /// iOS 17 上沙盒逃逸非必需(vfs 内核读写即可)
    static var requiresSandboxEscape: Bool { false }

    /// 只要 vfs 就绪就当作"有访问权限"
    static func hasSandboxAccess() -> Bool {
        return vfs_isready()
    }

    static func log(_ s: String) { NSLog("[AzTuT] %@", s) }
}

// MARK: - MCM 适配 (3105 的私有容器管理 API, 这里全部走 vfs 回退)
@discardableResult
func MCMActivateContainerPath(_ cls: Int, _ id: String, _ group: Bool, _ err: inout NSString?) -> String? {
    // 直接用 vfs 找容器
    if let p = AzTuTContainerFinder.container(for: id) { return p }
    err = "mcm unavailable (using vfs)"
    return nil
}

@discardableResult
func MCMActivateContainer(_ cls: Int, _ id: String, _ group: Bool, _ err: inout NSString?) -> Int64 {
    err = "mcm unavailable"
    return -1
}

func MCMEnumerateIdentifiersForClass(_ cls: UInt64, _ limit: Int, _ err: inout NSString?) -> [String] {
    // 用 vfs 枚举所有容器的 bundleID
    var out: [String] = []
    for e in AzTuTContainerFinder.listDir(AzTuTContainerFinder.appRoot) where e.isDir && e.name.count == 36 {
        let path = AzTuTContainerFinder.appRoot + "/" + e.name
        if let b = AzTuTContainerFinder.bundleID(ofContainer: path) { out.append(b) }
        if out.count >= limit { break }
    }
    return out
}

// MARK: - bad_query 适配 (3105 的 C 接口, 这里空实现)
func bad_query(_ path: UnsafeMutablePointer<Int8>?, _ max: Int64) -> UnsafeMutablePointer<CChar>? { nil }
func bad_query_release(_ h: Int32) { }
func bad_query_list(_ path: UnsafeMutablePointer<Int8>?, _ max: Int64) -> UnsafeMutablePointer<CChar>? { nil }

// MARK: - AppUtilityToolbar (从 3105 提取)
struct AppUtilityToolbar: ToolbarContent {
    let language: AppLanguage
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button(action: onOpenSettings) {
                    Label(language.text("settings.title"), systemImage: "gearshape")
                }
                Button(action: onOpenLogs) {
                    Label(language.text("accessibility.open_logs"), systemImage: "apple.terminal")
                }
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }
}
