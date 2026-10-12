//
//  AzTuTPatchApplier.swift
//  lara-cn / AzTuT
//
//  用 lara 的 vfs 内核层读写来应用 .3105 补丁包
//  —— 完全绕开 sandbox_escape / MCM 授权
//
import Foundation

/// 容器查找: bundleID -> 数据容器路径
enum AzTuTContainerFinder {

    static let appRoot = "/private/var/mobile/Containers/Data/Application"

    /// 列出所有数据容器 (内核层)
    static func listContainers() -> [String] {
        var out: UnsafeMutablePointer<vfs_entry_t>?
        var count: Int32 = 0
        guard vfs_listdir(appRoot, &out, &count) == 0, let entries = out else { return [] }
        defer { vfs_freelisting(entries) }
        var result: [String] = []
        for i in 0..<Int(count) {
            let e = entries[i]
            let name = withUnsafePointer(to: e.name) { p in
                p.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            if name.count == 36 { result.append(appRoot + "/" + name) }  // UUID 目录
        }
        return result
    }

    /// 读容器里的 metadata.plist, 拿 MCMMetadataIdentifier (= bundleID)
    static func bundleID(ofContainer path: String) -> String? {
        let meta = path + "/.com.apple.mobile_container_manager.metadata.plist"
        guard let data = vfsRead(meta) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return plist["MCMMetadataIdentifier"] as? String
    }

    static func vfsRead(_ path: String, maxSize: Int = 64 * 1024) -> Data? {
        let fsz = vfs_filesize(path)
        guard fsz > 0 else { return nil }
        let toRead = min(Int(fsz), maxSize)
        var buf = [UInt8](repeating: 0, count: toRead)
        let n = vfs_read(path, &buf, toRead, 0)
        guard n > 0 else { return nil }
        return Data(buf.prefix(Int(n)))
    }

    /// 找到指定 bundleID 的容器路径
    static func container(for bundleID: String) -> String? {
        for c in listContainers() {
            if self.bundleID(ofContainer: c) == bundleID { return c }
        }
        return nil
    }
}

/// 补丁应用结果
struct AzTuTApplyResult {
    var applied: Int = 0
    var failed: Int = 0
    var log: [String] = []
    var backupDir: String = ""
}

/// 用 vfs 内核写应用补丁
enum AzTuTPatchApplier {

    /// 备份目录 (放在本 App 自己的 Documents, 用普通写即可)
    static func backupRoot() -> String {
        let doc = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        let dir = doc + "/AzTuT_Backups"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 把解出的补丁应用到设备
    static func apply(project: PatchProject, password: String?) throws -> AzTuTApplyResult {
        var res = AzTuTApplyResult()
        let backupDir = backupRoot() + "/" + project.id.uuidString
        try? FileManager.default.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
        res.backupDir = backupDir
        res.log.append("补丁: \(project.name) 作者: \(project.author)")

        guard vfs_isready() else {
            res.log.append("❌ vfs 未就绪, 请先运行内核漏洞")
            return res
        }

        for rule in project.rules {
            let bundleID = rule.bundleID
            guard let container = AzTuTContainerFinder.container(for: bundleID) else {
                res.log.append("❌ 找不到容器: \(bundleID)")
                res.failed += 1
                continue
            }
            var rel = rule.relativePath
            if rel.hasPrefix("/") { rel.removeFirst() }
            let target = container + "/" + rel + "/" + rule.replacementFilename

            // 1. 备份原文件 (若存在)
            if vfs_filesize(target) > 0, let old = AzTuTContainerFinder.vfsRead(target, maxSize: 64*1024*1024) {
                let bpath = backupDir + "/" + rule.id.uuidString + ".orig"
                try? old.write(to: URL(fileURLWithPath: bpath))
                res.log.append("已备份: \(rule.relativePath)/\(rule.replacementFilename)")
            }

            // 2. 写入 (内核层)
            let ok = rule.replacementData.withUnsafeBytes { ptr -> Bool in
                guard let base = ptr.baseAddress else { return false }
                let n = vfs_write(target, base, rule.replacementData.count, 0)
                return n >= 0
            }
            if ok {
                res.applied += 1
                res.log.append("✅ \(rule.relativePath)/\(rule.replacementFilename) (\(rule.replacementData.count) 字节)")
            } else {
                res.failed += 1
                res.log.append("❌ 写入失败: \(rule.relativePath)/\(rule.replacementFilename)")
            }
        }
        return res
    }

    /// 从本地 .3105 文件读取并应用
    static func applyFromFile(_ url: URL, password: String?) throws -> AzTuTApplyResult {
        let data = try Data(contentsOf: url)
        let decoded = try PatchPackageCodec.decode(data, password: password)
        return try apply(project: decoded.project, password: password)
    }
}
