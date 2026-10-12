//
//  AzTuTView.swift — AzTuT 一键替换主界面 (中文 / 卡片式)
//
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class AzTuTModel: ObservableObject {
    @Published var logs: [String] = []
    @Published var busy = false
    @Published var kernelReady = false
    @Published var lastResult: String?

    func log(_ s: String) {
        logs.append(s)
    }

    func refreshKernel() {
        kernelReady = vfs_isready()
    }

    /// 用 .3105 包一键应用
    func applyPackage(url: URL, password: String?) {
        busy = true
        lastResult = nil
        Task.detached { [weak self] in
            guard let self else { return }
            var out: [String] = []
            do {
                let res = try AzTuTPatchApplier.applyFromFile(url, password: password)
                out = res.log
                out.insert("成功 \(res.applied) 项, 失败 \(res.failed) 项", at: 0)
                await MainActor.run { self.lastResult = "已应用: \(res.applied) 项" }
            } catch {
                out = ["❌ 应用失败: \(error.localizedDescription)"]
                await MainActor.run { self.lastResult = "失败" }
            }
            await MainActor.run {
                self.logs = out
                self.busy = false
                self.refreshKernel()
            }
        }
    }

    /// 手动替换某个位点(从文件选择器选源文件)
    func replace(game: AzTuTGame, slot: AzTuTSlot, sourceURL: URL) {
        busy = true
        Task.detached { [weak self] in
            guard let self else { return }
            var out: [String] = []
            defer { Task { @MainActor in self.busy = false } }
            guard let container = AzTuTContainerFinder.container(for: game.id) else {
                await MainActor.run { self.logs = ["❌ 找不到 \(game.name) 的容器"] }
                return
            }
            let dest = container + "/" + slot.relativeDir + "/" + sourceURL.lastPathComponent
            let data: Data
            do { data = try Data(contentsOf: sourceURL) }
            catch { await MainActor.run { self.logs = ["❌ 读源文件失败: \(error.localizedDescription)"] }; return }

            out.append("目标: \(dest)")
            let ok = data.withUnsafeBytes { ptr -> Bool in
                guard let base = ptr.baseAddress else { return false }
                return vfs_write(dest, base, data.count, 0) >= 0
            }
            out.append(ok ? "✅ 已写入 (\(data.count) 字节)" : "❌ 写入失败")
            await MainActor.run {
                self.logs = out
                self.lastResult = ok ? "替换成功" : "替换失败"
            }
        }
    }
}

struct AzTuTView: View {
    @StateObject private var model = AzTuTModel()
    @State private var expanded: Set<String> = []
    @State private var importing = false
    @State private var picking: (AzTuTGame, AzTuTSlot)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    packageCard
                    ForEach(AzTuTGameRegistry.games) { game in
                        gameCard(game)
                    }
                    logCard
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("AzTuT")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear { model.refreshKernel() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first {
                model.applyPackage(url: u, password: nil)
            }
        }
        .fileImporter(isPresented: Binding(
            get: { picking != nil },
            set: { if !$0 { picking = nil } }),
            allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first, let p = picking {
                model.replace(game: p.0, slot: p.1, sourceURL: u)
            }
            picking = nil
        }
    }

    // MARK: 状态卡
    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(model.kernelReady ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: model.kernelReady ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title3)
                    .foregroundStyle(model.kernelReady ? .green : .orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("内核状态").font(.headline)
                Text(model.kernelReady ? "读写已就绪" : "未就绪 · 请先在 Lara 页运行漏洞")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refreshKernel()
            } label: {
                Image(systemName: "arrow.clockwise").font(.headline)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(cardBG)
    }

    // MARK: 补丁包
    private var packageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("补丁包", systemImage: "shippingbox.fill")
                .font(.headline).foregroundStyle(.white)
            Text("导入 .3105 补丁包, 一键应用到对应游戏")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                importing = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down.on.square")
                    Text("导入并应用补丁包").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.black)
            }
            .disabled(model.busy)
        }
        .padding(16)
        .background(cardBG)
    }

    // MARK: 游戏卡
    private func gameCard(_ game: AzTuTGame) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded.contains(game.id) { expanded.remove(game.id) }
                else { expanded.insert(game.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: game.symbol)
                        .font(.title3).foregroundStyle(.orange)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.name).font(.headline).foregroundStyle(.white)
                        Text(game.id).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded.contains(game.id) ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if expanded.contains(game.id) {
                Divider().overlay(Color.white.opacity(0.08))
                ForEach(game.slots) { slot in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.label).font(.subheadline).foregroundStyle(.white)
                            Text("\(slot.relativeDir)/\(slot.filePattern)")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("选择文件替换") {
                            picking = (game, slot)
                        }
                        .font(.caption).buttonStyle(.bordered)
                        .tint(.orange)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .padding(.bottom, 8)
            }
        }
        .background(cardBG)
    }

    // MARK: 日志
    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("运行日志", systemImage: "doc.text.magnifyingglass").font(.headline)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            .foregroundStyle(.white)
            if model.logs.isEmpty {
                Text("暂无日志").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.logs.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(l.hasPrefix("❌") ? .red : (l.hasPrefix("✅") ? .green : .secondary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(cardBG)
    }

    private var cardBG: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
