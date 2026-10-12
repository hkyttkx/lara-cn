//
//  AzTuTPermissions.swift — 权限层适配
//  3105 原本用 MCM(bad_query) + KernelExploit 拿容器访问;
//  这里换成 lara 的 vfs, 所以把 3105 的权限符号做成适配/占位。
//
import Foundation
import SwiftUI

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
