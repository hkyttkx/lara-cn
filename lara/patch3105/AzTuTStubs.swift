//
//  AzTuTStubs.swift — 3105 里属于"壁纸/清理器/身份证明"等无关功能的占位
//  (AzTuT 只做补丁替换, 这些不启用)
//
import Foundation
import SwiftUI

// MARK: 壁纸
struct WallpaperStagedPackage: Identifiable, Hashable {
    let id: String
    var name: String = ""
    var displayName: String = ""
    var sizeBytes: Int64 = 0
    var descriptionText: String = ""
    var imageURLs: [URL] = []
}

struct WallpaperPackageStore {
    static let shared = WallpaperPackageStore()
    var packages: [WallpaperStagedPackage] = []
}

enum WallpaperLabError: Error {
    case unsupported
}

struct InstalledWallpaperPackageDetailView: View {
    var package: WallpaperStagedPackage
    var body: some View { EmptyView() }
}

// MARK: 清理器(占位, 不启用)
struct CleanerView: View {
    var body: some View { EmptyView() }
}

// MARK: 身份证明(占位)
struct DisplayIdentityAttestationToken: Codable, Hashable {
    var value: String = ""
}
