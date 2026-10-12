//
//  AzTuTView.swift — AzTuT 主界面 (中文 / 深色卡片 / 全功能)
//  补丁库 + 导入 + 制作 + 应用 + 恢复 + 多游戏快捷替换
//
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class AzTuTModel: ObservableObject {
    @Published var logs: [String] = []
    @Published var busy = false
    @Published var kernelReady = false
    @Published var info: String?

    func log(_ s: String) { logs.append(s) }
    func refreshKernel() { kernelReady = vfs_isready() }
}

struct AzTuTView: View {
    @StateObject private var model = AzTuTModel()
    @StateObject private var store = AzTuTPatchStore.shared
    @State private var importing = false
    @State private var expandedGame: String?
    @State private var picking: (AzTuTGame, AzTuTSlot)?
    @State private var showMaker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    if !store.installed.isEmpty { libraryCard }
                    importCard
                    makerCard
                    gamesCard
                    logCard
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("AzTuT")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showMaker = true } label: { Image(systemName: "plus.circle.fill") }
                        .tint(.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.refreshKernel() }
        .sheet(isPresented: $showMaker) {
            AzTuTMakerView(model: model)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first {
                model.busy = true
                switch store.importPackage(from: u) {
                case .success(let rec):
                    model.logs = ["✅ 已导入补丁: \(rec.name) (\(rec.rules.count) 条规则)"]
                    model.info = "已导入"
                case .failure(let e):
                    model.logs = ["❌ 导入失败: \(e.localizedDescription)"]
                }
                model.busy = false
            }
        }
        .fileImporter(isPresented: Binding(get: { picking != nil },
                                            set: { if !$0 { picking = nil } }),
                      allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first, let p = picking {
                do {
                    let data = try Data(contentsOf: u)
                    guard let container = AzTuTContainerFinder.container(for: p.0.id) else {
                        model.logs = ["❌ 找不到 \(p.0.name) 容器"]; picking = nil; return
                    }
                    let dest = container + "/" + p.1.relativeDir + "/" + u.lastPathComponent
                    let ok = data.withUnsafeBytes { ptr -> Bool in
                        guard let b = ptr.baseAddress else { return false }
                        return vfs_write(dest, b, data.count, 0) >= 0
                    }
                    model.logs = [ok ? "✅ 已写入 \(p.1.relativeDir)/\(u.lastPathComponent) (\(data.count)B)"
                                     : "❌ 写入失败"]
                    model.info = ok ? "替换成功" : "替换失败"
                } catch {
                    model.logs = ["❌ 读取失败: \(error.localizedDescription)"]
                }
                picking = nil
            }
        }
    }

    // MARK: 状态
    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(model.kernelReady ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: model.kernelReady ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title3).foregroundStyle(model.kernelReady ? .green : .orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("内核状态").font(.headline).foregroundStyle(.white)
                Text(model.kernelReady ? "读写已就绪" : "未就绪 · 请在「引擎」页运行漏洞+内核缓存+初始化")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.refreshKernel() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.white)
        }
        .padding(16).background(cardBG)
    }

    // MARK: 补丁库
    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("补丁库", systemImage: "tray.full.fill").font(.headline).foregroundStyle(.white)
            ForEach(store.installed) { rec in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.name).font(.subheadline).foregroundStyle(.white)
                            Text("作者 \(rec.author) · \(rec.rules.count) 条规则")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle().fill(rec.applied ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                    }
                    HStack(spacing: 8) {
                        Button(rec.applied ? "重新应用" : "应用") {
                            model.busy = true
                            let r = store.apply(rec)
                            model.logs = [okText(r, "应用")]; model.busy = false; model.refreshKernel()
                        }.buttonStyle(.borderedProminent).tint(.orange).font(.caption)
                        Button("恢复") {
                            model.busy = true
                            let r = store.restore(rec)
                            model.logs = [okText(r, "恢复")]; model.busy = false
                        }.buttonStyle(.bordered).tint(.blue).font(.caption)
                        Button(role: .destructive) { store.remove(rec) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.bordered).font(.caption)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            }
        }
        .padding(16).background(cardBG)
    }

    private func okText(_ r: Result<Void, Error>, _ verb: String) -> String {
        switch r {
        case .success: return "✅ \(verb)成功"
        case .failure(let e): return "❌ \(verb)失败: \(e.localizedDescription)"
        }
    }

    // MARK: 导入
    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("导入补丁包", systemImage: "shippingbox.fill").font(.headline).foregroundStyle(.white)
            Text("选择 .3105 补丁包, 自动识别目标游戏")
                .font(.caption).foregroundStyle(.secondary)
            Button { importing = true } label: {
                HStack { Image(systemName: "square.and.arrow.down")
                         Text("导入 .3105").fontWeight(.semibold) }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
            }.disabled(model.busy)
        }
        .padding(16).background(cardBG)
    }

    // MARK: 制作
    private var makerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("制作补丁", systemImage: "hammer.fill").font(.headline).foregroundStyle(.white)
            Text("选文件 + 指定游戏路径 → 导出成 .3105").font(.caption).foregroundStyle(.secondary)
            Button { showMaker = true } label: {
                HStack { Image(systemName: "wand.and.stars")
                         Text("新建补丁").fontWeight(.semibold) }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.orange)
            }
        }
        .padding(16).background(cardBG)
    }

    // MARK: 多游戏快捷
    private var gamesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("快捷替换", systemImage: "gamecontroller.fill")
                .font(.headline).foregroundStyle(.white).padding(16)
            ForEach(AzTuTGameRegistry.games) { game in
                VStack(spacing: 0) {
                    Button {
                        expandedGame = (expandedGame == game.id) ? nil : game.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: game.symbol).foregroundStyle(.orange).frame(width: 30)
                            Text(game.name).font(.subheadline).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: expandedGame == game.id ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }.buttonStyle(.plain)
                    if expandedGame == game.id {
                        ForEach(game.slots) { slot in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(slot.label).font(.caption).foregroundStyle(.white)
                                    Text("\(slot.relativeDir)/\(slot.filePattern)")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("选文件") { picking = (game, slot) }
                                    .font(.caption).buttonStyle(.bordered).tint(.orange)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                        }
                        .padding(.bottom, 6)
                    }
                }
            }
        }
        .padding(.vertical, 4).background(cardBG)
    }

    // MARK: 日志
    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("日志", systemImage: "doc.text.magnifyingglass").font(.headline)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }.foregroundStyle(.white)
            if model.logs.isEmpty { Text("暂无").font(.caption).foregroundStyle(.secondary) }
            else {
                ForEach(Array(model.logs.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(l.hasPrefix("❌") ? .red : (l.hasPrefix("✅") ? .green : .secondary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16).background(cardBG)
    }

    private var cardBG: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - 制作补丁界面
struct AzTuTMakerView: View {
    @ObservedObject var model: AzTuTModel
    @Environment(\.dismiss) var dismiss

    @State private var name = "我的补丁"
    @State private var author = "AzTuT"
    @State private var password = ""
    @State private var gameIdx = 0
    @State private var sourceURL: URL?
    @State private var pickingFile = false
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("补丁信息") {
                    TextField("名称", text: $name)
                    TextField("作者", text: $author)
                    TextField("密码(可空)", text: $password)
                }
                Section("目标游戏") {
                    Picker("游戏", selection: $gameIdx) {
                        ForEach(Array(AzTuTGameRegistry.games.enumerated()), id: \.offset) { i, g in
                            Text(g.name).tag(i)
                        }
                    }
                }
                Section("替换文件") {
                    Button(sourceURL == nil ? "选择文件" : "已选: \(sourceURL!.lastPathComponent)") {
                        pickingFile = true
                    }
                }
                Section {
                    Button("导出 .3105 补丁包") { doExport() }
                        .disabled(sourceURL == nil || exporting)
                }
            }
            .navigationTitle("新建补丁")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() } } }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { r in
            if case .success(let u) = r { sourceURL = u.first }
        }
    }

    private func doExport() {
        guard let src = sourceURL else { return }
        let game = AzTuTGameRegistry.games[gameIdx]
        // 默认放第一个 slot
        let slot = game.slots.first!
        do {
            let data = try Data(contentsOf: src)
            let outName = name.replacingOccurrences(of: " ", with: "_") + ".3105"
            let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(outName)
            let r = AzTuTPatchStore.shared.exportDraft(
                name: name, author: author,
                password: password.isEmpty ? nil : password,
                rules: [(game.id, slot.relativeDir, src.lastPathComponent, data)],
                to: out)
            switch r {
            case .success:
                model.logs = ["✅ 已导出: \(out.path)"]
                model.info = "导出成功"
                dismiss()
            case .failure(let e):
                model.logs = ["❌ 导出失败: \(e.localizedDescription)"]
            }
        } catch {
            model.logs = ["❌ 读取文件失败: \(error.localizedDescription)"]
        }
    }
}
