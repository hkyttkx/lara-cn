//
//  ContentView.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var mgr: laramgr
    @ObservedObject private var logger = globallogger
    @AppStorage("selectedMethod") private var selectedmethod: method = .hybrid
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggernobs: Bool = true
    
    @State private var showSettings: Bool = false
    @State private var dlingkcache: Bool = false
    
    init() {
        globallogger.capture()
    }
    
    var body: some View {
        NavigationStack {
            List {
                AlertsSection
                KRWSection
                RCSection
                ActionsSection
                DebugSection
                InlineLogsSection
            }
            .navigationTitle("Lara")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: {
                        mgr.showLogs.toggle()
                    }) {
                        Image(systemName: "terminal")
                    }
                }
                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: "gear")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
    
    private var AlertsSection: some View {
        Section {
            if !mgr.hasOffsets {
                PlainAlert(title: "未找到偏移！", icon: "exclamationmark.triangle.fill", text: "Kernelcache offsets are missing. Click \"Run Exploit\" and then fetch the offsets.")
            }
        }
    }
    
    private var KRWSection: some View {
        Section {
            LabeledContent(content: {
                if mgr.dsready {
                    Image(systemName: "checkmark.circle")
                } else if mgr.dsrunning {
                    HStack {
                        Text("\(Int(mgr.dsprogress * 100))%")
                        ProgressView()
                    }
                } else if mgr.dsattempted && mgr.dsfailed {
                    Image(systemName: "xmark.circle")
                }
            }) {
                Button("运行漏洞利用", action: {
                    offsets_init()
                    mgr.run()
                })
                .disabled(mgr.dsready || mgr.dsrunning || isdebugged())
            }
            
            if !mgr.hasOffsets {
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
            } else {
                if selectedmethod == .hybrid {
                    LabeledContent(content: {
                        if mgr.vfsready && mgr.sbxready {
                            Image(systemName: "checkmark.circle")
                        } else if mgr.vfsrunning || mgr.sbxrunning {
                            HStack {
                                Text("运行中…")
                                ProgressView()
                            }
                        } else if (mgr.vfsattempted && mgr.vfsfailed) || (mgr.sbxattempted && mgr.sbxfailed) {
                            Image(systemName: "xmark.circle")
                        }
                    }) {
                        Button("初始化系统", action: {
                            mgr.vfsinit()
                            mgr.sbxescape()
                        })
                        .disabled(!mgr.hasOffsets || !mgr.dsready || mgr.vfsrunning || mgr.sbxrunning || (mgr.vfsready && mgr.sbxready))
                    }
                }
                
                // initalize vfs
                if selectedmethod == .vfs {
                    LabeledContent(content: {
                        if mgr.vfsready {
                            Image(systemName: "checkmark.circle")
                        } else if mgr.vfsrunning {
                            HStack {
                                Text("\(Int(mgr.dsprogress * 100))%")
                                ProgressView()
                            }
                        } else if mgr.vfsattempted && mgr.vfsfailed {
                            Image(systemName: "xmark.circle")
                        }
                    }) {
                        Button("初始化虚拟文件系统", action: {
                            mgr.vfsinit()
                        })
                        .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning || isdebugged())
                    }
                }
                
                // escape sandbox
                if selectedmethod == .sbx {
                    LabeledContent(content: {
                        if mgr.sbxready {
                            Image(systemName: "checkmark.circle")
                        } else if mgr.sbxrunning {
                            HStack {
                                Text("运行中…")
                                ProgressView()
                            }
                        } else if mgr.sbxattempted && mgr.sbxfailed {
                            Image(systemName: "xmark.circle")
                        }
                    }) {
                        Button("逃逸沙盒", action: {
                            mgr.sbxescape()
                        })
                        .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning || isdebugged())
                    }
                }
            }
        } header: {
            HeaderLabel(text: "Kernel Read Write", icon: "externaldrive")
        } footer: {
            if isdebugged() {
                Text("调试器附加期间不可用")
            }
        }
    }
    
    private var RCSection: some View {
        Group {
            #if !DISABLE_REMOTECALL
            Section {
                // init remotecall
                LabeledContent(content: {
                    if mgr.rcready {
                        Image(systemName: "checkmark.circle")
                    } else if mgr.rcrunning {
                        HStack {
                            Text("运行中…")
                            ProgressView()
                        }
                    } else if mgr.rcfailed {
                        Image(systemName: "xmark.circle")
                    }
                }) {
                    Button("初始化远程调用", action: {
                        mgr.rcinit(process: "SpringBoard", migbypass: false) { success in
                            if success {
                                mgr.logmsg("rc init succeeded!")
                                let pid = mgr.rccall(name: "getpid")
                                mgr.logmsg("remote getpid() returned: \(pid)")
                            } else {
                                mgr.logmsg("rc init failed")
                                mgr.rcfailed = true
                            }
                        }
                    })
                    .disabled(!mgr.dsready || isdebugged() || mgr.rcrunning || mgr.rcready)
                }
                
                // destroy remotecall
                if mgr.rcready {
                    Button("销毁远程调用", action: {
                        mgr.rcdestroy()
                    })
                }
            } header: {
                HeaderLabel(text: "RemoteCall", icon: "syringe")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let error = mgr.rcLastError ?? mgr.sbProc?.lastError {
                        Text("错误：\(error)")
                            .foregroundColor(.red)
                    }
                    if RemoteCall.isLiveContainerRuntime() && !RemoteCall.isLiveProcessRuntime() {
                        Text("RemoteCall needs a PAC-enabled LiveContainer launch context. The main exploit may still work when RemoteCall is unavailable.")
                    }
                    if isdebugged() {
                        Text("附加调试器时不可用")
                    }
                    Text("远程调用不太稳定，可能无法正常工作。")
                    if isIOS16() {
                        Text("iOS 16 tip: Open Control Center after tapping Initialize RemoteCall. This significantly improves the success rate and speed.")
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Text("If initialization fails after about 2 minutes, respring, relaunch Lara, and try again.")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
                .font(.footnote)
            }
            #endif
        }
    }
    
    private var ActionsSection: some View {
        Section(header: HeaderLabel(text: "操作", icon: "wrench.and.screwdriver")) {
            Button("注销（Respring）", action: {
                mgr.respring()
            })
            
            Button("崩溃！", action: {
                mgr.panic()
            })
            
            if isdebugged() {
                Button("分离调试器", action: {
                    exit(0)
                })
            }
        }
    }
    
    private var DebugSection: some View {
        Group {
            if weonadebugbuild_pjbweouttahereexclamationmark {
                if mgr.dsready {
                    Section(header: HeaderLabel(text: "Debug Only", icon: "ant")) {
                        LabeledContent("kernel_base") {
                            Text(String(format: "0x%llx", mgr.kernbase))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("kernel_slide") {
                            Text(String(format: "0x%llx", mgr.kernslide))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var InlineLogsSection: some View {
        if selectedlogsdisplaymode == .content {
            Section {
                ScrollView {
                    if loggernobs {
                        let combined = logger.logs.joined(separator: "\n")
                        Text(combined)
                            .font(.system(size: 13, design: .monospaced))
                            .lineSpacing(1)
                            .textSelection(.enabled)
                            .onTapGesture {
                                UIPasteboard.general.string = combined
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    } else {
                        ForEach(Array(logger.logs.enumerated()), id: \.offset) { _, log in
                            Text(log)
                                .font(.system(size: 13, design: .monospaced))
                                .lineSpacing(1)
                                .textSelection(.enabled)
                                .onTapGesture {
                                    UIPasteboard.general.string = log
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        }
                    }
                }
                .frame(height: 250)
                
                Button("全部复制") {
                    UIPasteboard.general.string = logger.logs.joined(separator: "\n\n")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                
                Button("清除") {
                    logger.clear()
                }
                .foregroundColor(.red)
            } header: {
                HeaderLabel(text: "日志", icon: "terminal")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(laramgr())
}
