//
//  AceClassApp.swift
//  AceClass
//
//  Created by 陳麒畯 on 7/4/25.
//

import SwiftUI

@main
struct AceClassApp: App {
    // 補上 bookmarkKey 常數，與 ContentView.swift 保持一致
    private let bookmarkKey = "selectedFolderBookmark"
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // 1. 新增指令選單，提供全螢幕切換功能
        .commands {
            CommandGroup(after: .windowSize) {
                Button(action: {
                    toggleFullScreen()
                }) {
                    Text("進入/離開全螢幕")
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }
    }

    // init() {
    //     UserDefaults.standard.removeObject(forKey: bookmarkKey)
    //     print("已清除舊的 bookmarkKey，請重新選擇資料夾。")
    // }
    
    // 2. 新增切換全螢幕的輔助函式
    private func toggleFullScreen() {
        if let window = NSApplication.shared.windows.first {
            window.toggleFullScreen(nil)
        }
    }
}
