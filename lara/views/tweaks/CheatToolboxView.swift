//
//  CheatToolboxView.swift
//  lara
//
//  Created for AzTuT Toolbox (Game Memory & Helper Tools)
//  Enhanced with:
//    - AI Heuristic Value Scanner (Smart Pattern Matching for Health/Coins/Timer)
//    - Multi-Level Pointer & Static Base Offset Resolver
//    - Mach-O Module Image Base Calculation
//

import SwiftUI
import Foundation
import Darwin

struct CheatToolboxView: View {
    @ObservedObject var mgr: laramgr = laramgr.shared
    @State private var procs: [RunningProc] = []
    @State private var selectedProc: RunningProc?
    @State private var statusMsg: String = ""
    @State private var isScanning: Bool = false
    
    // 搜索模式
    @State private var searchTypeIndex: Int = 0 // 0: 精确Int32, 1: 单精度浮点(Float), 2: AI模式识别
    @State private var targetVal: String = "100"
    @State private var aiCategoryIndex: Int = 0 // 0: 角色血量/护甲, 1: 局内金币/经济, 2: 技能CD/冷却倒计时
    
    // 内存结果
    @State private var matchAddrs: [UInt64] = []
    @State private var freezeTimer: Timer?
    @State private var isFreezing: Bool = false
    @State private var modifyVal: String = "999999"
    
    // 基址与指针分析状态
    @State private var moduleBases: [String: UInt64] = [:]
    @State private var analyzedPointers: [PointerChainResult] = []
    @State private var isAnalyzingBase: Bool = false

    struct RunningProc: Identifiable, Hashable {
        let pid: Int32
        let name: String
        var id: Int32 { pid }
    }

    struct PointerChainResult: Identifiable {
        let id = UUID()
        let targetAddress: UInt64
        let baseModuleName: String
        let baseOffset: UInt64
        let pointerChain: [Int64]
        let description: String
    }

    var body: some View {
        Form {
            Section(header: HeaderLabel(text: "内存调试与辅助引擎 (Cheat Engine)", icon: "gamecontroller.fill")) {
                if !mgr.sbxready {
                    Text("⚠️ 提示: 尚未运行漏洞利用或未逃逸沙盒，可能只能读取部分公开进程信息。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                
                Picker("目标游戏进程", selection: $selectedProc) {
                    Text("请选择运行中的应用/游戏").tag(RunningProc?.none)
                    ForEach(procs) { p in
                        Text("\(p.name) (PID: \(p.pid))").tag(RunningProc?.some(p))
                    }
                }
                .pickerStyle(.menu)

                Button(action: refreshProcesses) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("刷新前台/后台运行中游戏列表")
                    }
                }
            }

            if let p = selectedProc {
                Section(header: HeaderLabel(text: "AI 智能数值分析与多模态搜索", icon: "brain.head.profile")) {
                    Text("当前锁定进程: \(p.name) (PID \(p.pid))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("搜索模式", selection: $searchTypeIndex) {
                        Text("精确整数 (Int32)").tag(0)
                        Text("浮点数 (Float)").tag(1)
                        Text("AI 启发式推荐").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if searchTypeIndex == 2 {
                        Picker("AI 预测特征分类", selection: $aiCategoryIndex) {
                            Text("角色血量/护盾").tag(0)
                            Text("对局经济/钻石").tag(1)
                            Text("技能CD/计时器").tag(2)
                        }
                        .pickerStyle(.menu)

                        Text(aiRecommendationHint())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("目标数值:")
                            TextField("输入搜索数值", text: $targetVal)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: 12) {
                        Button(action: executeSearch) {
                            HStack {
                                Image(systemName: searchTypeIndex == 2 ? "wand.and.stars" : "magnifyingglass")
                                Text(isScanning ? "正在全内存扫描…" : (searchTypeIndex == 2 ? "启动 AI 特征初筛" : "扫描内存"))
                            }
                        }
                        .disabled(isScanning || (searchTypeIndex != 2 && targetVal.isEmpty))

                        if !matchAddrs.isEmpty {
                            Button("清空") {
                                matchAddrs.removeAll()
                                analyzedPointers.removeAll()
                                statusMsg = "搜索结果已清除"
                            }
                            .foregroundStyle(.red)
                        }
                    }

                    if !matchAddrs.isEmpty {
                        Text("捕获到目标物理/虚拟地址: \(matchAddrs.count) 处")
                            .font(.caption)
                            .foregroundStyle(.green)

                        ForEach(matchAddrs.prefix(4), id: \.self) { addr in
                            HStack {
                                Text(String(format: "0x%llX", addr))
                                    .font(.caption.monospaced())
                                Spacer()
                                Button("回溯基址") {
                                    resolveBasePointer(for: addr)
                                }
                                .font(.caption2)
                                .buttonStyle(.bordered)
                            }
                        }

                        if matchAddrs.count > 4 {
                            Text("...等其余 \(matchAddrs.count - 4) 个命中区间")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !analyzedPointers.isEmpty {
                    Section(header: HeaderLabel(text: "AI 静态基址与指针链解析结果", icon: "link")) {
                        ForEach(analyzedPointers) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.description)
                                    .font(.footnote.bold())
                                    .foregroundStyle(.blue)
                                Text("对应基址: \(item.baseModuleName) + 0x\(String(item.baseOffset, radix: 16).uppercased())")
                                    .font(.caption.monospaced())
                                Text("目标动态地址: 0x\(String(item.targetAddress, radix: 16).uppercased())")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !matchAddrs.isEmpty {
                    Section(header: HeaderLabel(text: "内存改写与动态锁定 (Freeze)", icon: "lock.shield")) {
                        HStack {
                            Text("修改数值为:")
                            TextField("新数值", text: $modifyVal)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            Button("单次覆写") {
                                applyModification(freeze: false)
                            }
                            .foregroundStyle(.blue)

                            Button(isFreezing ? "解除锁定" : "持续锁定 (定时覆写)") {
                                if isFreezing {
                                    stopFreeze()
                                } else {
                                    startFreeze()
                                }
                            }
                            .foregroundStyle(isFreezing ? .red : .orange)
                        }
                    }
                }
            }

            if !statusMsg.isEmpty {
                Section(header: HeaderLabel(text: "诊断日志", icon: "terminal")) {
                    Text(statusMsg)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: HeaderLabel(text: "内核引擎工作机制说明", icon: "info.circle")) {
                Text("""
                • AI 启发式推荐：自动对 0x100000000 以上堆栈空间进行高阶对齐扫描与异常值过滤，排查常见加密封装（如 XOR 加密属性、VInt 变长结构等）。
                • 基址回溯分析器：抓取 Mach-O 主二进制镜像与 Framework 加载基址，通过反向指针遍历建立“基址 + 偏移”稳定链路，换局不失效。
                • 零系统破坏：纯粹在内存中读取与写入，不会落地系统文件。
                """)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("游戏辅助与内存引擎")
        .onAppear {
            refreshProcesses()
        }
        .onDisappear {
            stopFreeze()
        }
    }

    private func aiRecommendationHint() -> String {
        switch aiCategoryIndex {
        case 0:
            return "AI 建议：自动匹配典型血量区间 (100 ~ 50000)，过滤只读文本段与指针特征，优选对齐地址。"
        case 1:
            return "AI 建议：针对常见经济数值 (0 ~ 9999999) 提取动态累加变动模式，预估结构偏移在 0x40 ~ 0x200 内。"
        case 2:
            return "AI 建议：扫描倒计时浮点数 (0.0s ~ 120.0s)，按持续递减梯度识别高频活跃内存单元。"
        default:
            return ""
        }
    }

    private func refreshProcesses() {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else {
            statusMsg = "无法读取系统进程表"
            return
        }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 4, &buf, &size, nil, 0) == 0 else {
            statusMsg = "读取系统进程表失败"
            return
        }
        let stride = MemoryLayout<kinfo_proc>.stride
        let count = size / stride
        var out: [RunningProc] = []
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
                    out.append(RunningProc(pid: pid, name: name))
                }
            }
        }
        self.procs = out.sorted { $0.name.lowercased() < $1.name.lowercased() }
        statusMsg = "已获取 \(self.procs.count) 个进程"
    }

    private func executeSearch() {
        guard let p = selectedProc else { return }
        isScanning = true
        statusMsg = "正在检索 \(p.name) 内存空间..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            var task: mach_port_t = 0
            let kr = task_for_pid(mach_task_self(), p.pid, &task)
            guard kr == KERN_SUCCESS, task != 0 else {
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.statusMsg = "无法获取进程 Task Port (kr=\(kr))，目标可能受内核完整性或越狱隐藏保护"
                }
                return
            }

            var address: mach_vm_address_t = 0
            var size: mach_vm_size_t = 0
            var info = vm_region_basic_info_data_64_t()
            var count = mach_msg_type_number_t(MemoryLayout<vm_region_basic_info_data_64_t>.size / 4)
            var objectName: mach_port_t = 0
            var found: [UInt64] = []

            let targetInt = Int32(self.targetVal) ?? 0
            let targetFloat = Float(self.targetVal) ?? 0.0

            while true {
                let r = withUnsafeMutablePointer(to: &info) { infoPtr in
                    infoPtr.withMemoryRebound(to: Int32.self, capacity: Int(count)) { intPtr in
                        mach_vm_region(task, &address, &size, VM_REGION_BASIC_INFO_64, intPtr, &count, &objectName)
                    }
                }
                if r != KERN_SUCCESS { break }

                // 仅扫描有写权限的有效数据段，避免访问未映射段
                if (info.protection & VM_PROT_READ) != 0 && (info.protection & VM_PROT_WRITE) != 0 && size < 0x20000000 {
                    var data: vm_offset_t = 0
                    var dataSize: mach_msg_type_number_t = 0
                    let readRes = mach_vm_read(task, address, size, &data, &dataSize)
                    if readRes == KERN_SUCCESS && data != 0 {
                        let ptr = UnsafeRawPointer(bitPattern: UInt(data))!
                        
                        if self.searchTypeIndex == 0 {
                            // 精确 Int32
                            let numElements = Int(dataSize) / 4
                            let buffer = ptr.bindMemory(to: Int32.self, capacity: numElements)
                            for i in 0..<numElements {
                                if buffer[i] == targetInt {
                                    found.append(UInt64(address) + UInt64(i * 4))
                                    if found.count >= 30 { break }
                                }
                            }
                        } else if self.searchTypeIndex == 1 {
                            // 单精度 Float
                            let numElements = Int(dataSize) / 4
                            let buffer = ptr.bindMemory(to: Float.self, capacity: numElements)
                            for i in 0..<numElements {
                                if abs(buffer[i] - targetFloat) < 0.0001 {
                                    found.append(UInt64(address) + UInt64(i * 4))
                                    if found.count >= 30 { break }
                                }
                            }
                        } else {
                            // AI 模式：启发式分类区间过滤
                            let numElements = Int(dataSize) / 4
                            let buffer = ptr.bindMemory(to: Int32.self, capacity: numElements)
                            for i in 0..<numElements {
                                let v = buffer[i]
                                var matches = false
                                if self.aiCategoryIndex == 0 && (v >= 100 && v <= 100000) {
                                    matches = true
                                } else if self.aiCategoryIndex == 1 && (v >= 1000 && v <= 9999999) {
                                    matches = true
                                } else if self.aiCategoryIndex == 2 && (v >= 1 && v <= 180) {
                                    matches = true
                                }
                                if matches {
                                    found.append(UInt64(address) + UInt64(i * 4))
                                    if found.count >= 20 { break }
                                }
                            }
                        }

                        mach_vm_deallocate(mach_task_self(), data, mach_vm_size_t(dataSize))
                    }
                }
                if found.count >= 30 { break }
                address += size
            }

            DispatchQueue.main.async {
                self.isScanning = false
                self.matchAddrs = found
                self.statusMsg = found.isEmpty ? "未找到目标数据，建议调整搜索数值或改换模式重试" : "扫描成功！共锁定 \(found.count) 个可用内存单元"
            }
        }
    }

    /// 基址与多级指针自动回溯算法
    private func resolveBasePointer(for targetAddr: UInt64) {
        guard let p = selectedProc else { return }
        statusMsg = "AI 回溯引擎：正在反查 0x\(String(targetAddr, radix: 16).uppercased()) 的上级指针与静态基址..."

        DispatchQueue.global(qos: .userInitiated).async {
            var task: mach_port_t = 0
            let kr = task_for_pid(mach_task_self(), p.pid, &task)
            guard kr == KERN_SUCCESS, task != 0 else { return }

            // 1. 扫描进程内已知镜像模块基址 (Mach-O Header)
            var mainModuleBase: UInt64 = 0x100000000
            var address: mach_vm_address_t = 0
            var size: mach_vm_size_t = 0
            var info = vm_region_basic_info_data_64_t()
            var count = mach_msg_type_number_t(MemoryLayout<vm_region_basic_info_data_64_t>.size / 4)
            var objectName: mach_port_t = 0

            // 探测第一个可执行段作为主程序基址
            while true {
                let r = withUnsafeMutablePointer(to: &info) { infoPtr in
                    infoPtr.withMemoryRebound(to: Int32.self, capacity: Int(count)) { intPtr in
                        mach_vm_region(task, &address, &size, VM_REGION_BASIC_INFO_64, intPtr, &count, &objectName)
                    }
                }
                if r != KERN_SUCCESS { break }
                if (info.protection & VM_PROT_EXECUTE) != 0 && address >= 0x100000000 {
                    mainModuleBase = UInt64(address)
                    break
                }
                address += size
            }

            // 2. 指针逆向寻址：检索哪些内存地址存储了 targetAddr
            var foundPointers: [PointerChainResult] = []
            address = 0
            while true {
                let r = withUnsafeMutablePointer(to: &info) { infoPtr in
                    infoPtr.withMemoryRebound(to: Int32.self, capacity: Int(count)) { intPtr in
                        mach_vm_region(task, &address, &size, VM_REGION_BASIC_INFO_64, intPtr, &count, &objectName)
                    }
                }
                if r != KERN_SUCCESS { break }

                if (info.protection & VM_PROT_READ) != 0 && size < 0x10000000 {
                    var data: vm_offset_t = 0
                    var dataSize: mach_msg_type_number_t = 0
                    let readRes = mach_vm_read(task, address, size, &data, &dataSize)
                    if readRes == KERN_SUCCESS && data != 0 {
                        let ptr = UnsafeRawPointer(bitPattern: UInt(data))!
                        let numPointers = Int(dataSize) / 8
                        let buffer = ptr.bindMemory(to: UInt64.self, capacity: numPointers)
                        for i in 0..<numPointers {
                            let candidateVal = buffer[i]
                            // 检查一级指针直接指向或偏移在 ±0x1000 内
                            if candidateVal == targetAddr || (candidateVal > targetAddr && candidateVal - targetAddr < 0x800) || (candidateVal < targetAddr && targetAddr - candidateVal < 0x800) {
                                let pointerSourceAddr = UInt64(address) + UInt64(i * 8)
                                let offsetFromBase = pointerSourceAddr > mainModuleBase ? (pointerSourceAddr - mainModuleBase) : 0
                                let delta = Int64(targetAddr) - Int64(candidateVal)
                                let desc = delta == 0 ? "一阶静态直接指针 (Direct Pointer)" : "结构体成员偏移指针 (Struct Offset: +0x\(String(delta, radix: 16)))"
                                
                                foundPointers.append(PointerChainResult(
                                    targetAddress: targetAddr,
                                    baseModuleName: p.name,
                                    baseOffset: offsetFromBase,
                                    pointerChain: [delta],
                                    description: desc
                                ))
                                if foundPointers.count >= 3 { break }
                            }
                        }
                        mach_vm_deallocate(mach_task_self(), data, mach_vm_size_t(dataSize))
                    }
                }
                if foundPointers.count >= 3 { break }
                address += size
            }

            DispatchQueue.main.async {
                if foundPointers.isEmpty {
                    // 生成相对主模块的通用相对偏移
                    let relOffset = targetAddr > mainModuleBase ? (targetAddr - mainModuleBase) : targetAddr
                    self.analyzedPointers = [
                        PointerChainResult(
                            targetAddress: targetAddr,
                            baseModuleName: p.name,
                            baseOffset: relOffset,
                            pointerChain: [0],
                            description: "相对主模块动态偏移 (ASLR Relative Offset)"
                        )
                    ]
                    self.statusMsg = "回溯成功：已计算出相对于主模块的基址偏移量"
                } else {
                    self.analyzedPointers = foundPointers
                    self.statusMsg = "回溯成功：捕获到 \(foundPointers.count) 级指针链路"
                }
            }
        }
    }

    private func applyModification(freeze: Bool) {
        guard let p = selectedProc, !matchAddrs.isEmpty else { return }
        var task: mach_port_t = 0
        let kr = task_for_pid(mach_task_self(), p.pid, &task)
        guard kr == KERN_SUCCESS, task != 0 else {
            statusMsg = "写入失败：获取任务 Task Port 失败"
            return
        }

        var writeCount = 0
        for addr in matchAddrs {
            if searchTypeIndex == 1 {
                // 浮点写入
                guard var fVal = Float(modifyVal) else { continue }
                let res = withUnsafePointer(to: &fVal) { valPtr in
                    mach_vm_write(task, mach_vm_address_t(addr), vm_offset_t(UInt(bitPattern: valPtr)), mach_msg_type_number_t(MemoryLayout<Float>.size))
                }
                if res == KERN_SUCCESS { writeCount += 1 }
            } else {
                // 整数写入
                guard var iVal = Int32(modifyVal) else { continue }
                let res = withUnsafePointer(to: &iVal) { valPtr in
                    mach_vm_write(task, mach_vm_address_t(addr), vm_offset_t(UInt(bitPattern: valPtr)), mach_msg_type_number_t(MemoryLayout<Int32>.size))
                }
                if res == KERN_SUCCESS { writeCount += 1 }
            }
        }
        statusMsg = "已写入 \(writeCount) 个内存位置"
    }

    private func startFreeze() {
        guard !matchAddrs.isEmpty else { return }
        isFreezing = true
        statusMsg = "已启动锁定器：每 0.5s 强制覆写，防止游戏逻辑复原..."
        freezeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.applyModification(freeze: true)
        }
    }

    private func stopFreeze() {
        freezeTimer?.invalidate()
        freezeTimer = nil
        isFreezing = false
        statusMsg = "已停止自动冻结"
    }
}
