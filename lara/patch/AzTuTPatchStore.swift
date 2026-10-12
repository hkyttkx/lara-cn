//
//  AzTuTPatchStore.swift — AzTuT 补丁库 (本地保存/列出/删除)
//  复用 3105 的 .3105 包格式 (PatchPackageCodec)
//
import Foundation
import Combine

/// 已安装补丁的记录
struct AzTuTInstalledRecord: Codable, Identifiable {
    let id: UUID              // = project.id
    var name: String
    var author: String
    var installedAt: Date
    var applied: Bool         // 是否已应用
    var rules: [RuleSnapshot]

    struct RuleSnapshot: Codable {
        var bundleID: String
        var relativeDir: String
        var filename: String
        var backupPath: String?   // 原始文件备份(本App沙盒内)
        var hadOriginal: Bool
    }
}

@MainActor
final class AzTuTPatchStore: ObservableObject {
    static let shared = AzTuTPatchStore()

    @Published var installed: [AzTuTInstalledRecord] = []
    /// 用户自己做的补丁草稿(未打包)
    @Published var drafts: [PatchProject] = []

    private let fm = FileManager.default

    private var root: String {
        let doc = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        let r = doc + "/AzTuT"
        try? fm.createDirectory(atPath: r, withIntermediateDirectories: true)
        return r
    }
    private var indexPath: String { root + "/installed.json" }
    private var backupsDir: String { root + "/backups" }

    init() {
        try? fm.createDirectory(atPath: backupsDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: 持久化
    func load() {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: indexPath)),
              let list = try? JSONDecoder().decode([AzTuTInstalledRecord].self, from: d) else { return }
        installed = list
    }

    func save() {
        if let d = try? JSONEncoder().encode(installed) {
            try? d.write(to: URL(fileURLWithPath: indexPath))
        }
    }

    // MARK: 导入 .3105 → 存为补丁(不解密内容, 直接保留原包, 应用时再解)
    func importPackage(from url: URL) -> Result<AzTuTInstalledRecord, Error> {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try PatchPackageCodec.decode(data, password: nil)
            let proj = decoded.project
            // 保存原包
            let pkgDir = root + "/packages"
            try? fm.createDirectory(atPath: pkgDir, withIntermediateDirectories: true)
            let pkgPath = pkgDir + "/" + proj.id.uuidString + ".3105"
            try data.write(to: URL(fileURLWithPath: pkgPath))

            let rec = AzTuTInstalledRecord(
                id: proj.id, name: proj.name, author: proj.author,
                installedAt: Date(), applied: false,
                rules: proj.rules.map {
                    .init(bundleID: $0.bundleID,
                          relativeDir: $0.relativePath,
                          filename: $0.replacementFilename,
                          backupPath: nil, hadOriginal: false)
                })
            installed.removeAll { $0.id == rec.id }
            installed.append(rec)
            save()
            return .success(rec)
        } catch {
            return .failure(error)
        }
    }

    func packagePath(for id: UUID) -> String { root + "/packages/" + id.uuidString + ".3105" }

    func remove(_ rec: AzTuTInstalledRecord) {
        installed.removeAll { $0.id == rec.id }
        try? fm.removeItem(atPath: packagePath(for: rec.id))
        save()
    }

    // MARK: 应用
    func apply(_ rec: AzTuTInstalledRecord) -> Result<Void, Error> {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: packagePath(for: rec.id)))
            let decoded = try PatchPackageCodec.decode(data, password: nil)
            let proj = decoded.project
            guard vfs_isready() else { throw SimpleError("内核未就绪, 请先初始化") }

            for rule in proj.rules {
                guard let container = AzTuTContainerFinder.container(for: rule.bundleID) else {
                    throw SimpleError("找不到容器: \(rule.bundleID)")
                }
                let target = container + "/" + rule.relativePath + "/" + rule.replacementFilename
                // 备份原文件
                if vfs_filesize(target) > 0,
                   let old = AzTuTContainerFinder.vfsRead(target, maxSize: 128 * 1024 * 1024) {
                    let bdir = backupsDir + "/" + rec.id.uuidString
                    try? fm.createDirectory(atPath: bdir, withIntermediateDirectories: true)
                    try? old.write(to: URL(fileURLWithPath: bdir + "/" + rule.replacementFilename))
                }
                // 写入(内核层)
                let ok = rule.replacementData.withUnsafeBytes { p -> Bool in
                    guard let b = p.baseAddress else { return false }
                    return vfs_write(target, b, rule.replacementData.count, 0) >= 0
                }
                if !ok { throw SimpleError("写入失败: \(rule.replacementFilename)") }
            }
            if let i = installed.firstIndex(where: { $0.id == rec.id }) {
                installed[i].applied = true
                for j in installed[i].rules.indices {
                    installed[i].rules[j].hadOriginal = true
                    installed[i].rules[j].backupPath = backupsDir + "/" + rec.id.uuidString
                }
                save()
            }
            return .success(())
        } catch { return .failure(error) }
    }

    // MARK: 恢复
    func restore(_ rec: AzTuTInstalledRecord) -> Result<Void, Error> {
        do {
            guard vfs_isready() else { throw SimpleError("内核未就绪") }
            for r in rec.rules {
                guard let bdir = r.backupPath else { continue }
                let src = bdir + "/" + r.filename
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: src)) else { continue }
                guard let container = AzTuTContainerFinder.container(for: r.bundleID) else { continue }
                let target = container + "/" + r.relativeDir + "/" + r.filename
                _ = data.withUnsafeBytes { p -> Bool in
                    guard let b = p.baseAddress else { return false }
                    return vfs_write(target, b, data.count, 0) >= 0
                }
            }
            if let i = installed.firstIndex(where: { $0.id == rec.id }) {
                installed[i].applied = false; save()
            }
            return .success(())
        } catch { return .failure(error) }
    }

    // MARK: 制作自己的补丁(草稿 → 导出 .3105)
    func exportDraft(name: String, author: String, password: String?,
                     rules: [(bundleID: String, relativeDir: String, filename: String, data: Data)],
                     to outURL: URL) -> Result<Void, Error> {
        do {
            let prules = rules.map { r in
                PatchRule(bundleID: r.bundleID, relativePath: r.relativeDir,
                          replacementFilename: r.filename, replacementData: r.data)
            }
            let proj = PatchProject(name: name, author: author, rules: prules)
            let data = try PatchPackageCodec.encodeNew(project: proj, password: password).data
            try data.write(to: outURL)
            return .success(())
        } catch { return .failure(error) }
    }
}

struct SimpleError: LocalizedError {
    let msg: String
    init(_ m: String) { msg = m }
    var errorDescription: String? { msg }
}
