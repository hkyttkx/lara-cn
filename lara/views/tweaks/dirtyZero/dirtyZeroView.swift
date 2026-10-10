//
//  dirtyZeroView.swift
//  lara
//
//  Created by lunginspector on 5/14/26.
//

import SwiftUI

struct dirtyZeroView: View {
    @EnvironmentObject private var mgr: laramgr
    @AppStorage("tweakArray") var tweakArray: [ZeroSection] = TweakArray.tweaks
    @AppStorage("enableRiskyTweaks") var enableRiskyTweaks: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "操作", icon: "wrench.and.screwdriver"), footer: Text("All tweaks are done in memory, so if something goes wrong, please reboot your device. Made with love by [jailbreak.party](https://jailbreak.party). This section of tweaks is also available as a [seperate app!](https://github.com/jailbreakdotparty/dirtyZero)")) {
                    Button("应用调整", action: {
                        applyTweaks()
                    })
                    Button("注销（Respring）", action: {
                        mgr.respring()
                    })
                    Toggle("允许启用高风险未测试项目", isOn: $enableRiskyTweaks)
                }
                
                ListedTweaksSection
            }
            .navigationTitle("dirtyZero")
        }
    }
    
    private var ListedTweaksSection: some View {
        ForEach($tweakArray) { $section in
            if (section.name == "Risky Tweaks" && enableRiskyTweaks) || section.name != "Risky Tweaks" {
                Section(header: HeaderDropdown(text: section.name, icon: section.icon, isExpanded: $section.isExpanded, useItemCount: true, itemCount: section.tweaks.count)) {
                    if section.isExpanded {
                        ForEach($section.tweaks) { $tweak in
                            if (doubleSystemVersion() >= tweak.minSupportedVersion && doubleSystemVersion() <= tweak.maxSupportedVersion) || weonadebugbuild_pjbweouttahereexclamationmark {
                                PlainToggle(text: tweak.name, icon: tweak.icon, isOn: $tweak.isOn)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func applyTweaks() {
        let tweaks = tweakArray.flatMap { $0.tweaks }.filter { $0.isOn }
        
        for tweak in tweaks {
            for path in tweak.paths {
                _ = mgr.vfszeropage(at: path, dumb: true)
            }
        }
        
        Alertinator.shared.alert(title: "已尝试应用全部调整！", body: "Please respring your device to see any changes. Zeroing files with DarkSword is finicky, so you may have to apply multiple times!", actionLabel: "注销（Respring）", action: {
            mgr.respring()
        })
    }
}

// allows us to put arrays into AppStorage
extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }
    
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}
