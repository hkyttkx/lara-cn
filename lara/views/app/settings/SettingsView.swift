//
//  SettingsView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum method: String, CaseIterable {
    case vfs = "VFS"
    case sbx = "SBX"
    case hybrid = "Hybrid"
}

enum fmAppsDisplayMode: String, CaseIterable {
    case UUID = "UUID"
    case bundleID = "Bundle ID"
    case appName = "App Name"
}

enum logsdisplaymode: String, CaseIterable {
    case tabs = "In Tabs"
    case toolbar = "In Toolbar"
    case content = "Directly in ContentView"
}

struct SettingsView: View {
    @EnvironmentObject var mgr: laramgr
    
    @AppStorage("selectedMethod") private var selectedMethod: method = .hybrid
    @AppStorage("keepAlive") private var keepAlive: Bool = false
    @AppStorage("stashKRW") private var stashKRW: Bool = false
    @AppStorage("keepSpringBoardRemoteCallAliveIOS16") private var keepSpringBoardRemoteCallAliveIOS16: Bool = false
    
    @State private var dlingkcache: Bool = false
    @State private var showkcacheimport: Bool = false
    @State private var importingkcache: Bool = false
    @State private var showkcachetips: Bool = false
    @State private var stashingKRWNow: Bool = false
    
    @AppStorage("logsdisplaymode") private var selectedlogdisplaymode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggerNoBS: Bool = true
    
    @AppStorage("showFMInTabs") private var showFMInTabs: Bool = true
    @AppStorage("selectedFMAppsDisplayMode") private var selectedFMAppsDisplayMode: fmAppsDisplayMode = .appName
    @AppStorage("fmRecursiveSearch") private var fmRecursiveSearch: Bool = false
    
    @AppStorage("rcDockUnlimited") private var rcDockUnlimited: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "About", icon: "info.circle")) {
                    AppInfoCell()
                    NavigationLink("致谢", destination: CreditsView())
                }
                
                Section(header: HeaderLabel(text: "Exploit", icon: "ant")) {
                    Picker("", selection: $selectedMethod) {
                        ForEach(method.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    NavigationLink("修改偏移", destination: OffsetManagementView())
                }
                
                // kernelcache
                Section {
                    if !mgr.hasOffsets {
                        // this does not need to be here any longer, but i'll keep it here anyways.
                        Button {
                            guard !dlingkcache else { return }
                            dlingkcache = true

                            DispatchQueue.global(qos: .userInitiated).async {
                                let fetched = fetchkcache()

                                if fetched {
                                    let dlkc = dlkcache()
                                    DispatchQueue.main.async {
                                        mgr.hasOffsets = dlkc
                                        dlingkcache = false
                                    }
                                    return
                                }

                                DispatchQueue.main.async {
                                    mgr.hasOffsets = false
                                    dlingkcache = false
                                }
                            }
                        } label: {
                            if dlingkcache {
                                HStack {
                                    Text("正在获取内核缓存…")
                                    Spacer()
                                    ProgressView()
                                }
                            } else {
                                Text("获取内核缓存")
                            }
                        }
                        .disabled(dlingkcache || !mgr.dsready)
                               
                        LabeledContent(content: {
                            Button(action: {
                                showkcachetips.toggle()
                            }) {
                                Image(systemName: "info.circle")
                            }
                        }) {
                            Button("导入内核缓存", action: {
                                guard !importingkcache else { return }
                                showkcacheimport = true
                            })
                            .disabled(dlingkcache || importingkcache)
                        }
                    } else {
                        Button("移除内核缓存", action: {
                            Alertinator.shared.alert(title: "清除内核缓存数据？", body: "This will delete all kernelcache data and remove saved offsets. You will have to refetch the data to use lara again.", actionLabel: "Confirm", action: {
                                clearKcacheData()
                            })
                        })
                        .foregroundColor(.red)
                    }
                } header: {
                    HeaderLabel(text: "Kernelcache", icon: "cpu")
                } footer: {
                    if (!mgr.hasOffsets && (!mgr.dsready || (!mgr.vfsready && !mgr.sbxready))) {
                        Text("注意：你需要点击 \"Run Exploit\" before you can fetch kernelcache.\n\nDeleting and refetching kernelcache may fix some issues. Try doing this before opening a GitHub issue or asking for support in our [Discord](https://discord.gg/gw8PcRF3Jr) server.")
                    } else {
                        Text("Deleting and refetching kernelcache may fix some issues. Try doing this before opening a GitHub issue or asking for support in our [Discord](https://discord.gg/gw8PcRF3Jr) server.")
                    }
                }
                
                // tips
                if showkcachetips {
                    Section {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("如何获取内核缓存（macOS）")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.primary)
                            
                            Text("1. 下载适用于你设备的 IPSW 工具。")
                            Link("https://github.com/blacktop/ipsw/releases",
                                 destination: URL(string: "https://github.com/blacktop/ipsw/releases")!)
                            
                            Text("2. 解压压缩包。")
                            Text("3. 打开终端。")
                            Text("4. 进入解压后的目录：")
                            Text("cd /path/to/ipsw_3.1.671_something_something/")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(.primary)
                            
                            Text("5. 提取内核：")
                            Text("./ipsw extract --kernel [drag your ipsw here]")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(.primary)
                            
                            Text("6. 得到 kernelcache 文件。")
                            Text("7. 把 kernelcache 传到你的 iCloud 或 iPhone。")
                            Text("8. Tap the button above and select the kernelcache, for example kernelcache.release.iPhone14,3.")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: HeaderLabel(text: "App", icon: "gearshape"), footer: Text("若启用保活，应用被最小化后仍会继续运行。")) {
                    Toggle("Keep Alive", isOn: $keepAlive)
                        .onChange(of: keepAlive) { _ in
                            if keepAlive {
                                if !kaenabled { toggleka() }
                            } else {
                                if kaenabled { toggleka() }
                            }
                        }
                    Toggle("Disable Log Dividers", isOn: $loggerNoBS)
                    Picker("Logs Display", selection: $selectedlogdisplaymode) {
                        ForEach(logsdisplaymode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: HeaderLabel(text: "File Manager", icon: "folder"), footer: Text("Display Mode lets you change the way app folders get displayed in the file manager.")) {
                    Picker("Display Mode", selection: $selectedFMAppsDisplayMode) {
                        ForEach(fmAppsDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("Recursive Search in File Manager", isOn: $fmRecursiveSearch)
                    Toggle("Show File Manager in Tabs", isOn: $showFMInTabs)
                }
                
                #if !DISABLE_REMOTECALL
                Section(header: HeaderLabel(text: "RemoteCall", icon: "syringe")) {
                    Toggle("Stash KRW primitives", isOn: $stashKRW)
                        .onChange(of: stashKRW) { enabled in
                            if enabled && isIOS16() {
                                Alertinator.shared.alert(
                                    title: "iOS 16 警告",
                                    body: "Saving KRW on iOS 16 is currently unstable. If it fails, manually stash KRW a few more times."
                                )
                            }
                        }
                    if isIOS16() {
                        Toggle("Keep SpringBoard RemoteCall alive in background", isOn: $keepSpringBoardRemoteCallAliveIOS16)
                        Text("警告：远程调用激活时若退出应用，SpringBoard 可能注销")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.red)

                        Button {
                            guard !stashingKRWNow else { return }
                            stashingKRWNow = true
                            mgr.stashKRWToLaunchd { success in
                                stashingKRWNow = false
                                if success {
                                    Alertinator.shared.alert(
                                        title: "内核读写已缓存",
                                        body: "KRW primitives were successfully stashed to launchd."
                                    )
                                } else {
                                    let error = mgr.rcLastError ?? "Please try manually stashing KRW a few more times."
                                    Alertinator.shared.alert(
                                        title: "缓存内核读写失败",
                                        body: error
                                    )
                                }
                            }
                        } label: {
                            if stashingKRWNow {
                                HStack {
                                    Text("正在缓存内核读写到 launchd…")
                                    Spacer()
                                    ProgressView()
                                }
                            } else {
                                Text("立即缓存内核读写到 launchd")
                            }
                        }
                        .disabled(!mgr.dsready || mgr.rcrunning || stashingKRWNow)
                    }
                    Toggle("Allow >10 dock icons", isOn: $rcDockUnlimited)
                }
                #endif
            }
            .navigationTitle("设置")
            .fileImporter(isPresented: $showkcacheimport, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importingkcache = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        var ok = false
                        let shouldStopAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if shouldStopAccess {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        let fm = FileManager.default
                        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                            let dest = docs.appendingPathComponent("kernelcache")
                            do {
                                if fm.fileExists(atPath: dest.path) {
                                    try fm.removeItem(at: dest)
                                }
                                try fm.copyItem(at: url, to: dest)
                                ok = dlkcache()
                            } catch {
                                print("failed to import kernelcache: \(error)")
                                ok = false
                            }
                        }
                        DispatchQueue.main.async {
                            mgr.hasOffsets = ok
                            importingkcache = false
                        }
                    }
                case .failure:
                    break
                }
            }
        }
    }
    
    private func clearKcacheData() {
        let fm = FileManager.default
        
        UserDefaults.standard.removeObject(forKey: "lara.kernelcache_path")
        UserDefaults.standard.removeObject(forKey: "lara.kernelcache_size")
        
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let kernelcacheDocPath = docsPath.appendingPathComponent("kernelcache")
        
        do {
            if fm.fileExists(atPath: kernelcacheDocPath.path) {
                try fm.removeItem(at: kernelcacheDocPath)
                mgr.logmsg("Deleted kernelcache from Documents")
            }
        } catch {
            mgr.logmsg("失败 to delete kernelcache: \(error.localizedDescription)")
        }
        
        let tempPath = NSTemporaryDirectory()
        let tempFiles = ["kernelcache.release.ipad", "kernelcache.release.iphone", "kernelcache.release.ipad3", "kernelcache.release.iphone14,3"]
        
        for file in tempFiles {
            let path = tempPath + file
            do {
                if fm.fileExists(atPath: path) {
                    try fm.removeItem(atPath: path)
                    mgr.logmsg("Deleted temp kernelcache: \(file)")
                }
            } catch {
                mgr.logmsg("失败 to delete \(file): \(error.localizedDescription)")
            }
        }
        
        mgr.logmsg("Kernelcache data cleared")
        mgr.hasOffsets = false
    }
}
