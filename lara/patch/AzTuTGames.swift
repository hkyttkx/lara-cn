//
//  AzTuTGames.swift — AzTuT 支持的游戏与目标路径配置
//
import Foundation

/// 一个"可替换的文件位点"
struct AzTuTSlot: Identifiable, Hashable {
    let id = UUID()
    let label: String          // 中文说明, 例如 "社交大厅脚本"
    let relativeDir: String    // 容器内相对路径
    let filePattern: String    // 文件名(精确或后缀匹配)
}

/// 一个支持的 App(游戏)
struct AzTuTGame: Identifiable, Hashable {
    let id: String             // bundle identifier
    let name: String           // 中文名
    let symbol: String         // SF Symbol
    let slots: [AzTuTSlot]

    static func == (l: AzTuTGame, r: AzTuTGame) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum AzTuTGameRegistry {
    /// 内置支持的游戏清单
    static let games: [AzTuTGame] = [
        AzTuTGame(
            id: "com.tencent.smoba",
            name: "王者荣耀",
            symbol: "crown.fill",
            slots: [
                AzTuTSlot(label: "社交大厅脚本", relativeDir: "Documents/Pandora/program", filePattern: "socialbroker_lua64.bytes"),
                AzTuTSlot(label: "好友系统", relativeDir: "Documents/Pandora/program", filePattern: "findfriends_lua64.bytes"),
                AzTuTSlot(label: "外置载荷", relativeDir: "Documents/Pandora/temp", filePattern: "lua64_cache.pak"),
                AzTuTSlot(label: "全局绘制载荷", relativeDir: "Documents/Pandora", filePattern: "pandora_profile_overlay.js"),
            ]
        ),
        AzTuTGame(
            id: "com.tencent.ig",
            name: "和平精英",
            symbol: "scope",
            slots: [
                AzTuTSlot(label: "补丁存放目录", relativeDir: "Documents/ShadowTrackerExtra/Saved/Paks/puffer_temp", filePattern: "*.pak"),
            ]
        ),
        AzTuTGame(
            id: "com.tencent.tmgp.pubgmhd",
            name: "PUBG Mobile",
            symbol: "scope",
            slots: [
                AzTuTSlot(label: "补丁存放目录", relativeDir: "Documents/ShadowTrackerExtra/Saved/Paks/puffer_temp", filePattern: "*.pak"),
            ]
        ),
        AzTuTGame(
            id: "com.tencent.tmgp.dfm",
            name: "三角洲行动",
            symbol: "scope",
            slots: [
                AzTuTSlot(label: "脚本目录", relativeDir: "Documents/Pandora/program", filePattern: "*.bytes"),
            ]
        ),
    ]

    static func game(for bundleID: String) -> AzTuTGame? {
        games.first { $0.id == bundleID }
    }
}
