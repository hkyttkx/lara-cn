//
//  AzTuTVFS.swift — 基于 lara vfs 的容器查找与文件读写辅助
//
import Foundation

enum AzTuTContainerFinder {

    static let appRoot = "/private/var/mobile/Containers/Data/Application"

    /// 列目录 (vfs 内核层)
    static func listDir(_ path: String) -> [(name: String, isDir: Bool)] {
        guard vfs_isready() else { return [] }
        var out: UnsafeMutablePointer<vfs_entry_t>?
        var count: Int32 = 0
        guard vfs_listdir(path, &out, &count) == 0, let entries = out else { return [] }
        defer { vfs_freelisting(entries) }
        var res: [(String, Bool)] = []
        for i in 0..<Int(count) {
            let name = withUnsafePointer(to: entries[i].name) { p in
                p.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            res.append((name, entries[i].d_type == 4))
        }
        return res
    }

    /// 读文件 (vfs 内核层)
    static func vfsRead(_ path: String, maxSize: Int = 64 * 1024 * 1024) -> Data? {
        guard vfs_isready() else { return nil }
        let fsz = vfs_filesize(path)
        guard fsz > 0 else { return nil }
        let toRead = min(Int(fsz), maxSize)
        var buf = [UInt8](repeating: 0, count: toRead)
        let n = vfs_read(path, &buf, toRead, 0)
        guard n > 0 else { return nil }
        return Data(buf.prefix(Int(n)))
    }

    /// 写文件 (vfs 内核层)
    static func vfsWrite(_ path: String, data: Data) -> Bool {
        guard vfs_isready() else { return false }
        return data.withUnsafeBytes { p -> Bool in
            guard let b = p.baseAddress else { return false }
            return vfs_write(path, b, data.count, 0) >= 0
        }
    }

    /// 读容器 metadata 里的 bundleID
    static func bundleID(ofContainer path: String) -> String? {
        let meta = path + "/.com.apple.mobile_container_manager.metadata.plist"
        guard let data = vfsRead(meta, maxSize: 128 * 1024),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return plist["MCMMetadataIdentifier"] as? String
    }

    /// 找 bundleID 对应的容器路径
    static func container(for bundleID: String) -> String? {
        for e in listDir(appRoot) where e.isDir && e.name.count == 36 {
            let path = appRoot + "/" + e.name
            if self.bundleID(ofContainer: path) == bundleID { return path }
        }
        return nil
    }
}
