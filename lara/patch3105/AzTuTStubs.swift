//
//  AzTuTStubs.swift — 占位类型(3105 里属于壁纸/清理等无关功能的依赖)
//
import Foundation

/// 壁纸包(占位, 补丁功能不依赖其内部)
struct WallpaperStagedPackage: Identifiable, Hashable {
    let id: String
    var name: String = ""
    var sizeBytes: Int64 = 0
}

struct WallpaperImportFeedback: Identifiable {
    let id = UUID()
    var message: String = ""
}
