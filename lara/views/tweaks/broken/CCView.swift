//
//  CCView.swift
//  lara
//
//  Created by ruter on 16.04.26.
//

import SwiftUI

struct CCView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                } header: {
                    Text("控制中心注销")
                } footer: {
                    Text("使用应用内置的注销助手。")
                }
            }
            .navigationTitle("控制中心")
        }
    }
}
