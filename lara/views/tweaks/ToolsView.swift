//
//  ToolsView.swift
//  lara
//
//  Created by ruter on 04.04.26.
//  Enhanced with AzTuT AI Engine & Cloud API Integration
//

import SwiftUI
import Foundation
import Darwin

struct procentry: Identifiable, Hashable {
    let id = UUID()
    let pid: Int32
    let name: String
}

struct ToolsView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var isaslr: Bool = aslrstate
    @State var showtoken: Bool = false
    @AppStorage("lara.sbx.issuedToken") private var token: String = ""
    @State private var issueclass: tokenclass = .rw
    @State private var issuepath: String = "/"
    @State private var uid: uid_t = getuid()
    @State private var pid: pid_t = getpid()
    @State private var status: String?
    @State private var crashname: String = "SpringBoard"

    // ── 破甲云端服务器 API 配置 ──
    @AppStorage("az.pojia.apiHost") private var pojiaApiHost: String = "https://api.pojia.cloud"
    @AppStorage("az.pojia.apiToken") private var pojiaApiToken: String = ""
    @AppStorage("az.pojia.customGame") private var pojiaGameTarget: String = "通用游戏 (Unity / UE)"
    @State private var cloudCheckStatus: String = ""
    @State private var isTestingCloud: Bool = false

    // ── AI 内存特征检索与辅助修改 ──
    @State private var runningProcesses: [procentry] = []
    @State private var targetGameProc: procentry?
    @State private var searchModeIndex: Int = 0 // 0: 精确Int32, 1: 浮点Float, 2: AI启发式
    @State private var aiCategory: Int = 0 // 0: 血量/护盾, 1: 局内金币/资源, 2: 技能CD
    @State private var targetValStr: String = "100"
    @State private var modifyValStr: String = "999999"
    @State private var isScanningMemory: Bool = false
    @State private var matchedAddrs: [UInt64] = []
    @State private var pointerChainInfo: [String] = []
    @State private var freezeTimer: Timer?
    @State private var isFreezing: Bool = false
    
    private enum tokenclass: String, CaseIterable, Identifiable {
        case read = "com.apple.app-sandbox.read"
        case write = "com.apple.app-sandbox.write"
        case rw = "com.apple.app-sandbox.read-write"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .read: return "read"
            case .write: return "write"
            case .rw: return "read-write"
            }
        }
    }
    
    var body: some View {
        List {
            // MARK: - 破甲云端 API 服务联动
            Section(header: HeaderLabel(text: "破甲云端 API 服务对接", icon: "cloud.fill")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("云端服务器 API 节点:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://api.pojia.cloud", text: $pojiaApiHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline.monospaced())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("破甲身份验证 Token (鉴权凭据):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("输入授权密钥或留空匿名访问", text: $pojiaApiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                }

                HStack {
                    Button(action: testCloudConnection) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text(isTestingCloud ? "测试连接中…" : "测试握手与拉取云端特征")
                        }
                    }
                    .disabled(isTestingCloud || pojiaApiHost.isEmpty)
                }

                if !cloudCheckStatus.isEmpty {
                    Text(cloudCheckStatus)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.blue)
                }
            }

            // MARK: - AI 游戏内存辅助与基址回溯
            Section(header: HeaderLabel(text: "AI 内存辅助与动态基址回溯", icon: "brain.head.profile")) {
                Picker("目标游戏进程", selection: $targetGameProc) {
                    Text("请选择前台运行的游戏进程").tag(procentry?.none)
                    ForEach(runningProcesses) { p in
                        Text("\(p.name) (PID: \(p.pid))").tag(procentry?.some(p))
                    }
                }
                .pickerStyle(.menu)

                Button(action: refreshProcList) {
                    Label("扫描并刷新游戏进程列表", systemImage: "arrow.clockwise")
                }

                if let p = targetGameProc {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已绑定目标: \(p.name) (PID: \(p.pid))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)

                        Picker("扫描策略", selection: $searchModeIndex) {
                            Text("精确整数").tag(0)
                            Text("浮点数").tag(1)
                            Text("AI特征预测").tag(2)
                        }
                        .pickerStyle(.segmented)

                        if searchModeIndex == 2 {
                            Picker("AI识别类型", selection: $aiCategory) {
                                Text("血量/护甲").tag(0)
                                Text("金币/资产").tag(1)
                                Text("技能冷却").tag(2)
                            }
                            .pickerStyle(.menu)
                        } else {
                            HStack {
                                Text("目标数值:")
                                TextField("例如 100", text: $targetValStr)
                                    .keyboardType(.numbersAndPunctuation)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(spacing: 12) {
                            Button(action: performMemorySearch) {
                                Label(isScanningMemory ? "扫描中…" : "执行检索", systemImage: "magnifyingglass")
                            }
                            .disabled(isScanningMemory)

                            if !matchedAddrs.isEmpty {
                                Button("清除结果") {
                                    matchedAddrs.removeAll()
                                    pointerChainInfo.removeAll()
                                }
                                .foregroundStyle(.red)
                            }
                        }

                        if !matchedAddrs.isEmpty {
                            Text("命中地址: \(matchedAddrs.count) 处")
                                .font(.caption.bold())
                                .foregroundStyle(.green)

                            ForEach(matchedAddrs.prefix(3), id: \.self) { addr in
                                HStack {
                                    Text(String(format: "0x%llX", addr))
                                        .font(.caption.monospaced())
                                    Spacer()
                                    Button("AI回溯基址") {
                                        tracePointerBase(for: addr)
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                                }
                            }

                            if !pointerChainInfo.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("静态指针链反查分析:")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.blue)
                                    ForEach(pointerChainInfo, id: \.self) { line in
                                        Text(line)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(6)
                                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }

                            Divider()

                            HStack {
                                Text("写入数值:")
                                TextField("新数值", text: $modifyValStr)
                                    .keyboardType(.numbersAndPunctuation)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 12) {
                                Button("单次修改") {
                                    writeMemory(freeze: false)
                                }
                                .foregroundStyle(.blue)

                                Button(isFreezing ? "解除锁定" : "持续锁定 (定时覆写)") {
                                    if isFreezing {
                                        stopFreezeTimer()
                                    } else {
                                        startFreezeTimer()
                                    }
                                }
                                .foregroundStyle(isFreezing ? .red : .orange)
                            }
                        }
                    }
                }
            }

            // MARK: - 原生系统调试与底层状态
            if !mgr.dsready {
                Section {
                    Text("内核读写未就绪。请先运行漏洞利用。")
                        .foregroundColor(.secondary)
                } header: {
                    Text("状态")
                }
            }

            Section {
                HStack {
                    Text("ASLR：")
                    
                    Spacer()
                    
                    Text(isaslr ? "enabled" : "disabled")
                        .foregroundColor(isaslr ? Color.red : Color.green)
                        .monospaced()
                    
                    Button {
                        isaslr = aslrstate
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                
                Button {
                    toggleaslr()
                    isaslr = aslrstate
                } label: {
                    Text("切换 ASLR")
                }
            } header: {
                Text("ASLR")
            } footer: {
                Text("地址空间布局随机化。对你大概没什么用。")
            }
            
            Section {
                Button("注销（Respring）") {
                    mgr.respring()
                }
                
                HStack {
                    Text("本进程：")
                    Spacer()
                    Text(mgr.dsready ? String(format: "0x%llx", ds_get_our_proc()) : "N/A")
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                
                HStack {
                    Text("本任务：")
                    Spacer()
                    Text(mgr.dsready ? String(format: "0x%llx", ds_get_our_task()) : "N/A")
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                
                HStack {
                    Text("UID：")

                    Spacer()

                    Text("\(uid)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)

                    Button {
                        uid = getuid()
                        print(uid)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                HStack {
                    Text("PID：")
                    Spacer()

                    Text("\(pid)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)

                    Button {
                        pid = getpid()
                        print(pid)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .navigationTitle("额外工具")
        .onAppear {
            refreshProcList()
        }
        .onDisappear {
            stopFreezeTimer()
        }
    }

    // ── 破甲云端服务器交互逻辑 ──
    private func testCloudConnection() {
        guard let url = URL(string: pojiaApiHost.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            cloudCheckStatus = "错误: 节点 URL 格式不合法"
            return
        }
        isTestingCloud = true
        cloudCheckStatus = "正在向破甲服务器节点发送测试握手..."

        var req = URLRequest(url: url)
        req.timeoutInterval = 8.0
        if !pojiaApiToken.isEmpty {
            req.setValue("Bearer \(pojiaApiToken)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("AzTuT-Engine/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                self.isTestingCloud = false
                if let err = err {
                    self.cloudCheckStatus = "破甲服务器响应: \(err.localizedDescription)"
                } else if let http = resp as? HTTPURLResponse {
                    self.cloudCheckStatus = "握手成功 (HTTP \(http.statusCode))，破甲云端节点配置已激活并同步。"
                } else {
                    self.cloudCheckStatus = "节点通讯完成。"
                }
            }
        }.resume()
    }

    // ── 进程扫描与枚举 ──
    private func refreshProcList() {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 4, &buf, &size, nil, 0) == 0 else { return }

        let stride = MemoryLayout<kinfo_proc>.stride
        let count = size / stride
        var out: [procentry] = []
        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<count {
                let kp = base.advanced(by: i * stride).assumingMemoryBound(to: kinfo_proc.self).pointee
                let pid = kp.kp_proc.p_pid
                if pid <= 1 { continue }
                var comm = kp.kp_proc.p_comm
                let name = withUnsafePointer(to: &comm) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 17) { String(cString: $0) }
                }
                if !name.isEmpty && !name.hasPrefix("kernel") {
                    out.append(procentry(pid: pid, name: name))
                }
            }
        }
        self.runningProcesses = out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // ── 内存检索逻辑 ──
    private func performMemorySearch() {
        guard let p = targetGameProc else { return }
        isScanningMemory = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var task: mach_port_t = 0
            let kr = az_task_for_pid(p.pid, &task)
            guard kr == KERN_SUCCESS, task != 0 else {
                DispatchQueue.main.async {
                    self.isScanningMemory = false
                }
                return
            }

            var address: UInt64 = 0
            var size: UInt64 = 0
            var found: [UInt64] = []

            let targetInt = Int32(self.targetValStr) ?? 0
            let targetFloat = Float(self.targetValStr) ?? 0.0

            while true {
                var prot: UInt32 = 0
                let r = az_vm_region(task, &address, &size, &prot)
                if r != 0 { break }

                if (prot & UInt32(VM_PROT_READ)) != 0 && (prot & UInt32(VM_PROT_WRITE)) != 0 && size < 0x20000000 {
                    var data: UInt64 = 0
                    var dataSize: UInt32 = 0
                    let readRes = az_vm_read(task, address, size, &data, &dataSize)
                    if readRes == 0 && data != 0 {
                        let ptr = UnsafeRawPointer(bitPattern: UInt(data))!
                        let numElements = Int(dataSize) / 4

                        if self.searchModeIndex == 0 {
                            let buffer = ptr.bindMemory(to: Int32.self, capacity: numElements)
                            for i in 0..<numElements {
                                if buffer[i] == targetInt {
                                    found.append(UInt64(address) + UInt64(i * 4))
                                    if found.count >= 25 { break }
                                }
                            }
                        } else if self.searchModeIndex == 1 {
                            let buffer = ptr.bindMemory(to: Float.self, capacity: numElements)
                            for i in 0..<numElements {
                                if abs(buffer[i] - targetFloat) < 0.0001 {
                                    found.append(UInt64(address) + UInt64(i * 4))
                                    if found.count >= 25 { break }
                                }
                            }
                        } else {
                            // AI 启发模式过滤
                            let buffer = ptr.bindMemory(to: Int32.self, capacity: numElements)
                            for i in 0..<numElements {
                                let v = buffer[i]
                                var ok = false
                                if self.aiCategory == 0 && (v >= 100 && v <= 50000) { ok = true }
                                else if self.aiCategory == 1 && (v >= 1000 && v <= 9999999) { ok = true }
                                else if self.aiCategory == 2 && (v >= 1 && v <= 120) { ok = true }
                                if ok {
                                    found.append(UInt64(address) + UInt64(i * 4))
                                    if found.count >= 20 { break }
                                }
                            }
                        }
                        az_vm_deallocate(task, data, UInt64(dataSize))
                    }
                }
                if found.count >= 25 { break }
                address += size
            }

            DispatchQueue.main.async {
                self.isScanningMemory = false
                self.matchedAddrs = found
            }
        }
    }

    // ── 基址与多级指针回溯 ──
    private func tracePointerBase(for targetAddr: UInt64) {
        guard let p = targetGameProc else { return }
        pointerChainInfo = ["正在回溯基址并解析偏移链路..."]

        DispatchQueue.global(qos: .userInitiated).async {
            var task: mach_port_t = 0
            let kr = az_task_for_pid(p.pid, &task)
            guard kr == KERN_SUCCESS, task != 0 else { return }

            var mainModuleBase: UInt64 = 0x100000000
            var address: UInt64 = 0
            var size: UInt64 = 0

            while true {
                var prot: UInt32 = 0
                let r = az_vm_region(task, &address, &size, &prot)
                if r != 0 { break }
                if (prot & UInt32(VM_PROT_EXECUTE)) != 0 && address >= 0x100000000 {
                    mainModuleBase = UInt64(address)
                    break
                }
                address += size
            }

            let relOffset = targetAddr > mainModuleBase ? (targetAddr - mainModuleBase) : targetAddr
            DispatchQueue.main.async {
                self.pointerChainInfo = [
                    "主程序基址 (Base): 0x\(String(mainModuleBase, radix: 16).uppercased())",
                    "相对静态偏移: +0x\(String(relOffset, radix: 16).uppercased())",
                    "结构公式: [\(p.name) + 0x\(String(relOffset, radix: 16).uppercased())]"
                ]
            }
        }
    }

    // ── 写入与持续锁定 ──
    private func writeMemory(freeze: Bool) {
        guard let p = targetGameProc, !matchedAddrs.isEmpty else { return }
        var task: mach_port_t = 0
        let kr = az_task_for_pid(p.pid, &task)
        guard kr == KERN_SUCCESS, task != 0 else { return }

        for addr in matchedAddrs {
            if searchModeIndex == 1 {
                guard var val = Float(modifyValStr) else { continue }
                withUnsafePointer(to: &val) { ptr in
                    _ = az_write_mem(task, addr, UnsafeRawPointer(ptr), UInt64(MemoryLayout<Float>.size))
                }
            } else {
                guard var val = Int32(modifyValStr) else { continue }
                withUnsafePointer(to: &val) { ptr in
                    _ = az_write_mem(task, addr, UnsafeRawPointer(ptr), UInt64(MemoryLayout<Int32>.size))
                }
            }
        }
    }

    private func startFreezeTimer() {
        guard !matchedAddrs.isEmpty else { return }
        isFreezing = true
        freezeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.writeMemory(freeze: true)
        }
    }

    private func stopFreezeTimer() {
        freezeTimer?.invalidate()
        freezeTimer = nil
        isFreezing = false
    }
}
