//
//  ShowHiddenIconsView.swift
//  lara
//

import SwiftUI

struct ShowHiddenIconsView: View {
    @ObservedObject var mgr: laramgr

    private let key = "SBIconVisibility"
    private let path = fileloc.globalprefs.rawValue

    @State private var isEnabled = false
    @State private var isLoading = false
    @State private var status: String?
    @State private var confirmRebuildDB = false

    var body: some View {
        List {
            Section(
                header: HeaderLabel(text: "Home Screen", icon: "app.badge"),
                footer: Text("灵感来自 Nugget 的 \"Show Hidden Icons on Home Screen\" tweak. Writes SBIconVisibility to GlobalPreferences. This may not take effect until SpringBoard's Application State DB is rebuilt.")
            ) {
                Toggle("显示隐藏图标", isOn: Binding(
                    get: { isEnabled },
                    set: { setEnabled($0) }
                ))
                .disabled(isLoading || !canWrite)

                HStack {
                    Text("偏好设置")
                    Spacer()
                    Text(isEnabled ? "Enabled" : "Disabled")
                        .foregroundColor(isEnabled ? .green : .secondary)
                        .monospaced()
                }
            }

            Section(
                header: HeaderLabel(text: "操作", icon: "wrench.and.screwdriver"),
                footer: Text("Refresh only reloads the current SBIconVisibility value from GlobalPreferences. It does not rebuild SpringBoard caches.")
            ) {
                Button {
                    loadState()
                } label: {
                    if isLoading {
                        HStack {
                            Text("正在刷新…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("刷新偏好设置状态")
                    }
                }
                .disabled(isLoading || !canWrite)

                HStack {
                    Button(role: .destructive) {
                        reset()
                    } label: {
                        Text("移除偏好")
                    }
                    .disabled(isLoading || !canWrite)

                    Spacer()

                    Button {
                        Alertinator.shared.alert(
                            title: "移除偏好",
                            body: "Deletes the SBIconVisibility key from GlobalPreferences instead of writing false. This restores the default preference value. If SpringBoard has already cached the old state, you may still need to rebuild the Application State DB and reboot."
                        )
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Button(role: .destructive) {
                        confirmRebuildDB = true
                    } label: {
                        Text("重建应用状态数据库")
                    }
                    .disabled(isLoading || !canWrite)

                    Spacer()

                    Button {
                        Alertinator.shared.alert(
                            title: "重建应用状态数据库",
                            body: "Clears SpringBoard's applicationState.db, applicationState.db-wal, and applicationState.db-shm so SpringBoard rebuilds them. Reboot after applying. Respring may leave SpringBoard on a black screen, and some widget configuration may be lost."
                        )
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("显示隐藏图标")
        .onAppear {
            loadState()
        }
        .alert("显示隐藏图标", isPresented: .constant(status != nil)) {
            Button("确定") { status = nil }
        } message: {
            Text(status ?? "")
        }
        .alert("重建应用状态数据库？", isPresented: $confirmRebuildDB) {
            Button("取消", role: .cancel) {}
            Button("重建", role: .destructive) {
                rebuildApplicationStateDB()
            }
        } message: {
            Text("与 Nugget 的 \"Rebuild SpringBoard Application State DB\" option. It replaces SpringBoard's applicationState.db with an empty file so SpringBoard can rebuild it. You should reboot the device after applying. Respring may leave SpringBoard on a black screen. Rebuilding this DB can also reset some app/widget state, including widget configuration. Continue only if you accept that risk.")
        }
    }

    private var canWrite: Bool {
        mgr.sbxready || mgr.vfsready
    }

    private func loadState() {
        guard canWrite else {
            status = "Sandbox escape or VFS is not ready."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let result = mgr.getplistvalue(path: path, key: key)
        if result.ok, let value = result.value as? Bool {
            isEnabled = value
        } else {
            isEnabled = false
        }
    }

    private func setEnabled(_ enabled: Bool) {
        guard canWrite else {
            status = "Sandbox escape or VFS is not ready."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let result = mgr.setplistvalue(
            path: path,
            key: (key, enabled ? true : nil),
            force: true
        )

        if result.ok {
            isEnabled = enabled
            status = enabled
                ? "SBIconVisibility enabled. If there is no visible effect, you may need to rebuild SpringBoard's Application State DB, then reboot the device."
                : "SBIconVisibility preference removed. If there is no visible effect, rebuild SpringBoard's Application State DB, then reboot the device."
        } else {
            status = result.message
            loadState()
        }
    }

    private func reset() {
        setEnabled(false)
    }

    private func rebuildApplicationStateDB() {
        guard canWrite else {
            status = "Sandbox escape or VFS is not ready."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let dbPaths = [
            "/var/mobile/Library/FrontBoard/applicationState.db",
            "/var/mobile/Library/FrontBoard/applicationState.db-wal",
            "/var/mobile/Library/FrontBoard/applicationState.db-shm",
        ]

        var failures: [String] = []
        for dbPath in dbPaths {
            let result = mgr.lara_overwritefile(target: dbPath, data: Data())
            if !result.ok {
                failures.append("\(dbPath): \(result.message)")
            }
        }

        if failures.isEmpty {
            status = "Application State DB cleared. Reboot the device now. Do not rely on respring; it may leave SpringBoard on a black screen. Some widget configuration may be lost."
        } else {
            status = failures.joined(separator: "\n")
        }
    }
}

#Preview {
    NavigationStack {
        ShowHiddenIconsView(mgr: laramgr.shared)
    }
}
