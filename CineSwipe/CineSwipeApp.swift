//
//  CineSwipeApp.swift
//  CineSwipe
//
//  Created by dejun pi on 2026/8/25.
//

import SwiftData
import SwiftUI

@main
struct CineSwipeApp: App {
    private let modelContainer: ModelContainer
    private let startupError: String?

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 30 * 1024 * 1024,
            diskCapacity: 150 * 1024 * 1024,
            diskPath: "CineSwipeImages"
        )

        do {
            modelContainer = try ModelContainer(
                for: LibraryItem.self,
                SkippedItem.self
            )
            startupError = nil
        } catch {
            startupError = "本地存储暂时不可用，请重新启动 App。"
            let configuration = ModelConfiguration(
                isStoredInMemoryOnly: true
            )
            do {
                modelContainer = try ModelContainer(
                    for: LibraryItem.self,
                    SkippedItem.self,
                    configurations: configuration
                )
            } catch {
                fatalError("无法初始化 SwiftData：\(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(startupError: startupError)
        }
        .modelContainer(modelContainer)
    }
}
