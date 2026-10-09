//
//  DirectoryView.swift
//  lara
//
//  Created by lunginspector on 5/22/26.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

struct santanderitem: Identifiable, Hashable {
    let path: String
    let name: String
    let display: String
    let isApp: Bool
    let appUDID: String
    let isdir: Bool
    let type: UTType?

    var id: String { path }

    init(path: String, isdir: Bool, display: String? = nil, isApp: Bool = false, appUDID: String = "") {
        self.path = path
        self.isdir = isdir
        let name = path == "/" ? "/" : (path as NSString).lastPathComponent
        self.name = name
        self.isApp = isApp
        self.appUDID = appUDID
        self.display = display ?? name
        let ext = (path as NSString).pathExtension
        self.type = ext.isEmpty ? nil : UTType(filenameExtension: ext)
    }

    var icon: String {
        if isdir { return "folder.fill" }
        guard let type else { return "doc" }
        if type.isSubtype(of: .text) { return "doc.text" }
        if type.isSubtype(of: .image) { return "photo" }
        if type.isSubtype(of: .audio) { return "waveform" }
        if type.isSubtype(of: .movie) || type.isSubtype(of: .video) { return "play.rectangle" }
        return "doc"
    }
}

final class santanderdirmodel: ObservableObject {
    @Published var allitems: [santanderitem] = []
    @Published var shownitems: [santanderitem] = []
    @Published var emptymsg: String?
    @Published var loading = false

    let item: santanderitem
    let readsbx: Bool
    let writevfs: Bool

    var sort: santandersort = .az
    var showhidden = true
    var recsearch = false

    init(item: santanderitem, readsbx: Bool, writevfs: Bool) {
        self.item = item
        self.readsbx = readsbx
        self.writevfs = writevfs
    }

    func load(query: String = "") {
        loading = true
        let item = item
        let readsbx = readsbx
        let sort = sort
        let showhidden = showhidden
        let recsearch = recsearch

        DispatchQueue.global(qos: .userInitiated).async {
            let listing = santanderfs.listdir(item: item, readsbx: readsbx)
            let shown = santanderfs.filteritems(
                all: listing.items,
                base: item.path,
                query: query,
                showhidden: showhidden,
                recsearch: recsearch,
                sort: sort,
                readsbx: readsbx
            )
            let empty = santanderfs.emptymessage(
                shown: shown,
                all: listing.items,
                query: query,
                showhidden: showhidden,
                fallback: listing.empty
            )

            DispatchQueue.main.async {
                self.allitems = listing.items
                self.shownitems = shown
                self.emptymsg = empty
                self.loading = false
            }
        }
    }
}

struct santanderdirview: View {
    let item: santanderitem
    let readsbx: Bool
    let writevfs: Bool

    @EnvironmentObject private var nav: santandernav
    @ObservedObject private var clip = santanderclip.shared
    @AppStorage("fmRecursiveSearch") private var recsearch = false

    @StateObject private var model: santanderdirmodel
    @State private var query = ""
    @State private var showimport = false
    @State private var msg: santandermsg?
    @State private var infoitem: santanderitem?
    @State private var chmoditem: santanderitem?
    @State private var chownitem: santanderitem?
    @State private var delitem: santanderitem?
    @State private var renameitem: santanderitem?
    @State private var shownewfolder = false
    @State private var shownewfile = false
    @State private var showvfsinfo = false

    init(item: santanderitem, readsbx: Bool, writevfs: Bool) {
        self.item = item
        self.readsbx = readsbx
        self.writevfs = writevfs
        _model = StateObject(wrappedValue: santanderdirmodel(item: item, readsbx: readsbx, writevfs: writevfs))
    }

    var body: some View {
        List {
            if model.loading && model.shownitems.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if model.shownitems.isEmpty {
                Section {
                    Text(model.emptymsg ?? "Directory is empty.")
                        .foregroundColor(.secondary)
                }
            } else {
                Section {
                    ForEach(model.shownitems) { entry in
                        Button {
                            nav.stack.append(entry)
                        } label: {
                            row(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                copy(entry)
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }

                            Button {
                                infoitem = entry
                            } label: {
                                Label("查看信息", systemImage: "info.circle")
                            }

                            Button {
                                share(entry)
                            } label: {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }

                            Button {
                                renameitem = entry
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .disabled(!readsbx)

                            Button {
                                replace(entry)
                            } label: {
                                Label("用剪贴板替换", systemImage: "doc.on.clipboard")
                            }
                            .disabled(clip.item == nil || (!readsbx && !writevfs))

                            Button {
                                chmoditem = entry
                            } label: {
                                Label("修改权限", systemImage: "lock.open")
                            }

                            Button {
                                chownitem = entry
                            } label: {
                                Label("修改属主", systemImage: "person.crop.circle")
                            }

                            Button(role: .destructive) {
                                delitem = entry
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    if !readsbx {
                        Text("This file manager is powered by vfs namecache lookups, not full directory enumeration. It may display inaccurate information.")
                    }
                }
            }
        }
        .navigationTitle(item.path == "/" ? "/" : item.name)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear {
            syncsettings()
            model.load()
        }
        .onChange(of: query) { newvalue in
            syncsettings()
            model.load(query: newvalue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .onChange(of: recsearch) { _ in
            syncsettings()
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .refreshable {
            syncsettings()
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !readsbx {
                    Button {
                        showvfsinfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }

                Menu {
                    Button {
                        if readsbx {
                            showimport = true
                        } else {
                            msg = santandermsg(title: "上传不可用", text: "Upload is only supported in SBX mode.")
                        }
                    } label: {
                        Label("上传文件", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        if readsbx {
                            shownewfolder = true
                        } else {
                            msg = santandermsg(title: "新建文件夹不可用", text: "Creating folders is only supported in SBX mode.")
                        }
                    } label: {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }

                    Button {
                        if readsbx {
                            shownewfile = true
                        } else {
                            msg = santandermsg(title: "创建文件不可用", text: "Creating files is only supported in SBX mode.")
                        }
                    } label: {
                        Label("新建文件", systemImage: "doc.badge.plus")
                    }

                    Button {
                        paste(replace: false)
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    .disabled(clip.item == nil || !readsbx)

                    Button {
                        paste(replace: true)
                    } label: {
                        Label("粘贴（替换）", systemImage: "doc.on.clipboard.fill")
                    }
                    .disabled(clip.item == nil || !readsbx)

                    Menu {
                        Button("按 A-Z 排序") {
                            model.sort = .az
                            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        Button("按 Z-A 排序") {
                            model.sort = .za
                            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    } label: {
                        Label("排序", systemImage: "arrow.up.arrow.down")
                    }

                    Button {
                        model.showhidden.toggle()
                        model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        Label(model.showhidden ? "Hide hidden files" : "Display hidden files", systemImage: "eye")
                    }

                    Button {
                        nav.go(santanderitem(path: "/", isdir: true))
                    } label: {
                        Label("前往根目录", systemImage: "externaldrive")
                    }

                    Button {
                        nav.go(santanderitem(path: NSHomeDirectory(), isdir: true))
                    } label: {
                        Label("前往主目录", systemImage: "house")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fileImporter(isPresented: $showimport, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                upload(url)
            case .failure(let err):
                msg = santandermsg(title: "上传失败", text: err.localizedDescription)
            }
        }
        .alert(item: $msg) { msg in
            Alert(title: Text(msg.title), message: Text(msg.text), dismissButton: .default(Text("确定")))
        }
        .alert("删除", isPresented: Binding(get: { delitem != nil }, set: { if !$0 { delitem = nil } })) {
            Button("取消", role: .cancel) {
                delitem = nil
            }
            Button("删除", role: .destructive) {
                if let entry = delitem {
                    delete(entry)
                }
                delitem = nil
            }
        } message: {
            Text("删除 \(delitem?.name ?? "item")?")
        }
        .sheet(item: $infoitem) { entry in
            infosheetcontent(entry: entry)
        }
        .sheet(item: $renameitem) { entry in
            santandernamesheet(
                title: "重命名",
                itemname: entry.name,
                placeholder: entry.name,
                actiontitle: "重命名"
            ) { newname in
                rename(entry, newname: newname)
            }
        }
        .sheet(item: $chmoditem) { entry in
            santanderchmodsheet(item: entry) { mode in
                santanderfs.clearImmutableIfPossible(atPath: entry.path)
                let ok = entry.path.withCString { apfs_mod($0, mode) == 0 }
                msg = santandermsg(title: "修改权限", text: ok ? "Operation completed." : "Operation failed.")
            }
        }
        .sheet(item: $chownitem) { entry in
            santanderchownsheet(item: entry) { uid, gid in
                santanderfs.clearImmutableIfPossible(atPath: entry.path)
                let ok = entry.path.withCString { apfs_own($0, uid, gid) == 0 }
                msg = santandermsg(title: "修改属主", text: ok ? "Operation completed." : "Operation failed.")
            }
        }
        .alert("文件管理器信息", isPresented: $showvfsinfo) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("This browser is powered by vfs namecache lookups, not full directory enumeration. Some folders may appear empty unless entries are already cached. Symlinks may also be shown as files even when their targets are directories.")
        }
        .sheet(isPresented: $shownewfolder) {
            santandernamesheet(
                title: "新建文件夹",
                itemname: item.name,
                placeholder: "新建文件夹",
                actiontitle: "创建"
            ) { name in
                newfolder(name: name)
            }
        }
        .sheet(isPresented: $shownewfile) {
            santandernewfilesheet(itemname: item.name) { name, text in
                newfile(name: name, text: text)
            }
        }
    }

    private func syncsettings() {
        model.recsearch = recsearch
    }

    @ViewBuilder
    private func row(entry: santanderitem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.icon)
                .foregroundColor(entry.isdir ? .accentColor : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.display)
                    .foregroundColor(entry.name.hasPrefix(".") ? .gray : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if entry.isApp {
                    Text(entry.appUDID)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(entry.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if entry.isdir {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
        }
        .contentShape(Rectangle())
    }

    private func copy(_ entry: santanderitem) {
        clip.item = santanderclipitem(path: entry.path, isdir: entry.isdir, name: entry.name)
        msg = santandermsg(title: "已复制", text: entry.name)
    }

    private func rename(_ entry: santanderitem, newname: String) {
        guard readsbx else {
            msg = santandermsg(title: "重命名不可用", text: "Rename is only supported in SBX mode.")
            return
        }

        let trimmed = newname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            msg = santandermsg(title: "重命名失败", text: "Name cannot be empty.")
            return
        }
        guard !trimmed.contains("/") else {
            msg = santandermsg(title: "重命名失败", text: "Name cannot contain '/'.")
            return
        }
        guard trimmed != entry.name else { return }

        let dest = ((entry.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: dest) else {
            msg = santandermsg(title: "重命名失败", text: "A file with that name already exists.")
            return
        }

        do {
            santanderfs.clearImmutableIfPossible(atPath: entry.path)
            try FileManager.default.moveItem(atPath: entry.path, toPath: dest)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "重命名失败", text: error.localizedDescription)
        }
    }

    private func newfolder(name: String) {
        guard readsbx else {
            msg = santandermsg(title: "新建文件夹不可用", text: "Creating folders is only supported in SBX mode.")
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            msg = santandermsg(title: "新建文件夹失败", text: "Name cannot be empty.")
            return
        }
        guard !trimmed.contains("/") else {
            msg = santandermsg(title: "新建文件夹失败", text: "Name cannot contain '/'.")
            return
        }

        let dest = (item.path as NSString).appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: dest) else {
            msg = santandermsg(title: "新建文件夹失败", text: "A file with that name already exists.")
            return
        }

        do {
            try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: false, attributes: nil)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "新建文件夹失败", text: error.localizedDescription)
        }
    }

    private func newfile(name: String, text: String) {
        guard readsbx else {
            msg = santandermsg(title: "创建文件不可用", text: "Creating files is only supported in SBX mode.")
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            msg = santandermsg(title: "创建文件失败", text: "Name cannot be empty.")
            return
        }
        guard !trimmed.contains("/") else {
            msg = santandermsg(title: "创建文件失败", text: "Name cannot contain '/'.")
            return
        }

        let dest = (item.path as NSString).appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: dest) else {
            msg = santandermsg(title: "创建文件失败", text: "A file with that name already exists.")
            return
        }

        do {
            try Data(text.utf8).write(to: URL(fileURLWithPath: dest), options: .atomic)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "创建文件失败", text: error.localizedDescription)
        }
    }

    private func paste(replace: Bool) {
        guard readsbx else {
            msg = santandermsg(title: "粘贴不可用", text: "Paste is only supported in SBX mode.")
            return
        }
        guard let clipitem = clip.item else { return }

        if clipitem.isdir && (item.path == clipitem.path || item.path.hasPrefix(clipitem.path + "/")) {
            msg = santandermsg(title: "粘贴失败", text: "Cannot paste a folder into itself.")
            return
        }

        let base = (item.path as NSString).appendingPathComponent(clipitem.name)
        let dest = replace ? base : santanderfs.uniquepath(base: base)

        do {
            if replace && FileManager.default.fileExists(atPath: dest) {
                try santanderfs.removeItemClearingImmutable(atPath: dest)
            }
            try FileManager.default.copyItem(atPath: clipitem.path, toPath: dest)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "粘贴失败", text: error.localizedDescription)
        }
    }

    private func replace(_ entry: santanderitem) {
        guard let clipitem = clip.item else { return }

        if writevfs && !entry.isdir && !clipitem.isdir {
            let ok = laramgr.shared.vfsoverwritefromlocalpath(target: entry.path, source: clipitem.path)
            if ok {
                model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                msg = santandermsg(title: "替换失败", text: "VFS overwrite failed.")
            }
            return
        }

        guard readsbx else {
            msg = santandermsg(title: "替换不可用", text: "Replace is only supported in SBX mode.")
            return
        }

        if clipitem.isdir && (entry.path == clipitem.path || entry.path.hasPrefix(clipitem.path + "/")) {
            msg = santandermsg(title: "替换失败", text: "Cannot replace with a folder into itself.")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: entry.path) {
                try santanderfs.removeItemClearingImmutable(atPath: entry.path)
            }
            try FileManager.default.copyItem(atPath: clipitem.path, toPath: entry.path)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "替换失败", text: error.localizedDescription)
        }
    }

    private func delete(_ entry: santanderitem) {
        guard readsbx else {
            msg = santandermsg(title: "删除 Unavailable", text: "删除 is only supported in SBX mode.")
            return
        }

        do {
            try santanderfs.removeItemClearingImmutable(atPath: entry.path)
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "删除 Failed", text: error.localizedDescription)
        }
    }

    @MainActor
    private func share(_ entry: santanderitem) {
        guard readsbx else {
            msg = santandermsg(title: "分享不可用", text: "Share is only supported in SBX mode.")
            return
        }
        guard !entry.isdir else {
            msg = santandermsg(title: "分享不可用", text: "Sharing folders is not supported.")
            return
        }
        guard FileManager.default.isReadableFile(atPath: entry.path) else {
            msg = santandermsg(title: "分享失败", text: "File is not readable.")
            return
        }

        presentShareSheet(with: URL(fileURLWithPath: entry.path))
    }

    private func upload(_ url: URL) {
        guard readsbx else {
            msg = santandermsg(title: "上传不可用", text: "Upload is only supported in SBX mode.")
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            msg = santandermsg(title: "上传失败", text: "Unable to access selected file.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let base = (item.path as NSString).appendingPathComponent(url.lastPathComponent)
        let dest = santanderfs.uniquepath(base: base)

        do {
            if FileManager.default.fileExists(atPath: dest) {
                try santanderfs.removeItemClearingImmutable(atPath: dest)
            }
            try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: dest))
            model.load(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            msg = santandermsg(title: "上传失败", text: error.localizedDescription)
        }
    }
}
