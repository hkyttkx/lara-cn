//
//  AzTuTCustom.swift — 用户自定义游戏与路径 (持久化)
//
import Foundation
import Combine

/// 用户自定义的一个"游戏(或App)"
struct AzTuTCustomGame: Codable, Identifiable, Hashable {
    var id: String          // bundle identifier
    var name: String
    var symbol: String      // SF Symbol 名
    var slots: [AzTuTCustomSlot]
}

struct AzTuTCustomSlot: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String
    var relativeDir: String
    var filePattern: String
}

@MainActor
final class AzTuTCustomStore: ObservableObject {
    static let shared = AzTuTCustomStore()
    @Published var games: [AzTuTCustomGame] = []

    private let key = "aztut_custom_games"

    init() { load() }

    func load() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let g = try? JSONDecoder().decode([AzTuTCustomGame].self, from: d) else { return }
        games = g
    }

    func save() {
        if let d = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    func add(_ g: AzTuTCustomGame) {
        games.removeAll { $0.id == g.id }
        games.append(g)
        save()
    }

    func remove(_ g: AzTuTCustomGame) {
        games.removeAll { $0.id == g.id }
        save()
    }
}
