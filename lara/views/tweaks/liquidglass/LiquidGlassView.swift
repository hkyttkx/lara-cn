//
//  LGView.swift
//  lara
//
//  Created by jurre111 on 24.04.26.
//

// Credits to leminlimez and Duy Tran for most of the code
// thank you lunginspector for the rewrite

import SwiftUI

let gpCurrentPath = "/var/Managed Preferences/mobile/.GlobalPreferences.plist"

struct LiquidGlassView: View {
    @EnvironmentObject private var mgr: laramgr
    
    @State private var gpCurrentDict: NSMutableDictionary = NSMutableDictionary()
    @State private var trueBool: Bool = true
    
    @State private var dumbassToggleThatMakesTheViewUpdate: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "Applying", icon: "checkmark")) {
                    Button("应用调整", action: { applyLiquidGlass() })
                    Button("重置调整", action: { restoreLiquidGlass() })
                }
                
                Section(header: HeaderLabel(text: "Preview", icon: "eye")) {
                    LiquidGlassPreview(lgDisabled: gpKeyBinding("com.apple.SwiftUI.DisableSolarium"), lgFallback: gpKeyBinding("SolariumForceFallback"))
                        .listRowInsets(EdgeInsets())
                }
                
                Section(header: HeaderLabel(text: "User Interface", icon: "iphone"), footer: Text("Solarium Fallback - This will give all liquid glass elements a gray background.\n\nDisable Liquid Glass - This will actually disable liquid glass, reverting back to the iOS 18 UI, with some major visual bugs (especially in the Control Center).")) {
                    Toggle("强制使用 Solarium 回退模式", isOn: gpKeyBinding("SolariumForceFallback"))
                    Toggle("完全禁用 Liquid Glass 视觉渲染", isOn: gpKeyBinding("com.apple.SwiftUI.DisableSolarium"))
                }
                
                Section(header: HeaderLabel(text: "液态玻璃", icon: "square.on.square.intersection.dashed")) {
                    Toggle("关闭镜面动态反射粒子", isOn: gpKeyBinding("SBDisableSpecularEverywhereUsingLSSAssertion"))
                    Toggle("禁用外部毛玻璃折射渲染", isOn: gpKeyBinding("SolariumDisableOuterRefraction"))
                    Toggle("关闭系统 Solarium HDR 显示", isOn: gpKeyBinding("SolariumAllowHDR", default: true, enable: false))
                }
                
                Section(header: HeaderLabel(text: "Visibility", icon: "loupe")) {
                    Toggle("跳过 Liquid Glass 版本号强制校验", isOn: gpKeyBinding("com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck"))
                    Toggle("关闭锁屏时钟高斯模糊", isOn: gpKeyBinding("SBDisallowGlassTime"))
                    Toggle("关闭 Dock 栏 Liquid Glass 模糊", isOn: gpKeyBinding("SBDisableGlassDock"))
                }
            }
            .navigationTitle("液态玻璃")
            .onAppear {
                loadGPData()
            }
        }
    }
    
    // MARK: file loading functions. root you said that making my comments uppercase sounds like i'm vibecoding so this will all be lowercase from now on.
    private func loadGPData() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let gpSavedURL = docsDir.appendingPathComponent("已保存GlobalPrefs.plist")
        let gpCurrentURL = URL(fileURLWithPath: gpCurrentPath)
        
        do {
            if !FileManager.default.fileExists(atPath: gpSavedURL.path) {
                try FileManager.default.copyItem(at: gpCurrentURL, to: gpSavedURL)
            }
            chmod(gpSavedURL.path, 0o644)
            
            gpCurrentDict = try NSMutableDictionary(contentsOf: URL(fileURLWithPath: gpCurrentPath), error: ())
        } catch {
            Alertinator.shared.alert(title: "加载全局偏好数据失败！", body: "Please restart the app and try again.")
        }
    }
    
    // MARK: applying/reloading functions
    func applyLiquidGlass() {
        do {
            let gpData = try verifyPlist(gpCurrentDict, targetPath: gpCurrentPath)
            let result = mgr.lara_overwritefile(target: gpCurrentPath, data: gpData)
            
            if result.ok {
                Alertinator.shared.alert(title: "液态玻璃效果已应用！", body: "Reboot your device to see any changes")
            } else {
                throw "Overwrite failed: \(result.message)"
            }
        } catch {
            Alertinator.shared.alert(title: "启用液态玻璃效果失败！", body: "\(error)")
        }
    }
    
    func restoreLiquidGlass() {
        do {
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let gpSavedURL = docsDir.appendingPathComponent("已保存GlobalPrefs.plist")
            
            if FileManager.default.fileExists(atPath: gpSavedURL.path) {
                let restored = try NSMutableDictionary(contentsOf: gpSavedURL, error: ())
                _ = try verifyPlist(restored, targetPath: mgCurrentPath)
                gpCurrentDict = restored
            } else {
                throw "No Global Prefs file found!"
            }
        } catch {
            Alertinator.shared.alert(title: "还原液态玻璃失败！", body: "\(error)")
        }
    }
    
    // MARK: bindings
    private func gpKeyBinding<T: Equatable>(_ key: String, type: T.Type = Bool.self, default: T? = false, enable: T? = true) -> Binding<Bool> {
        return Binding(get: {
            _ = dumbassToggleThatMakesTheViewUpdate
            if let value = gpCurrentDict[key] as? T?, let enable {
                return value == enable
            }
            return false
        }, set: { enabled in
            if enabled {
                dumbassToggleThatMakesTheViewUpdate.toggle()
                gpCurrentDict[key] = enable
            } else {
                dumbassToggleThatMakesTheViewUpdate.toggle()
                gpCurrentDict.removeObject(forKey: key)
            }
        })
    }
}

#Preview {
    LiquidGlassView()
}
