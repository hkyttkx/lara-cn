//
//  TweaksView.swift
//  lara
//
//  Created by lunginspector on 5/3/26.
//

import SwiftUI

struct TweaksView: View {
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @ObservedObject var mgr: laramgr
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "SpringBoard", icon: "house")) {
                    NavigationLink("远程调用定制", destination: RemoteView(mgr: mgr))
                        .disabled(!mgr.rcready)
                    NavigationLink("液态玻璃", destination: LiquidGlassView())
                        .disabled(!mgr.vfsready)
                    NavigationLink("SpringBoard 定制", destination: SpringBoardView(mgr: mgr))
                        .disabled(!mgr.vfsready)
                }
                
                Section(header: HeaderLabel(text: "Lock Screen", icon: "lock")) {
                    NavigationLink("锁屏密码主题", destination: PasscodeView(mgr: mgr))
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "Apps", icon: "app")) {
                    NavigationLink("卡牌覆盖", destination: CardView())
                        .disabled(!mgr.vfsready)
                    NavigationLink("应用解密", destination: DecryptView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("3 应用限制绕过", destination: AppsView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("移出黑名单", destination: WhitelistView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("JIT 启用器", destination: JitView())
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "User Interface", icon: "eye")) {
                    NavigationLink("dirtyZero", destination: dirtyZeroView())
                        .disabled(!mgr.vfsready)
                    NavigationLink("显示隐藏图标", destination: ShowHiddenIconsView(mgr: mgr))
                        .disabled(!mgr.sbxready && !mgr.vfsready)
                    NavigationLink("设备信息（Gestalt）", destination: GestaltView(mgr: mgr))
                        .disabled(!mgr.sbxready)
                    NavigationLink("字体覆盖", destination: FontPicker(mgr: mgr))
                        .disabled(!mgr.vfsready)
                    NavigationLink("系统配色修补", destination: SystemColor(mgr: mgr))
                        .disabled(!mgr.sbxready || !mgr.vfsready)
                }
                
                Section(header: HeaderLabel(text: "System", icon: "gear")) {
                    NavigationLink("变量清理", destination: VarCleanView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("自定义覆盖", destination: CustomView(mgr: mgr))
                        .disabled(!mgr.vfsready)
                    NavigationLink("OTA 更新", destination: OTAView(mgr: mgr))
                    NavigationLink("屏幕使用时间", destination: ScreenTimeView(mgr: mgr))
                }
                
                Section(header: HeaderLabel(text: "Broken", icon: "exclamationmark.triangle.fill")) {
                    NavigationLink("暗色面板", destination: DarkBoardView())
                        .disabled(true)
                }
                
                NavigationLink("额外工具", destination: ToolsView())
            }
            .disabled(!mgr.dsready)
            .navigationTitle("功能调整")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: {
                        mgr.showLogs.toggle()
                    }) {
                        Image(systemName: "terminal")
                    }
                }
            }
        }
    }
}
