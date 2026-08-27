import SwiftData
import SwiftUI

struct ContentView: View {
    let startupError: String?
    @StateObject private var viewModel = CineSwipeViewModel()
    @Environment(\.modelContext) private var modelContext

    init(startupError: String? = nil) {
        self.startupError = startupError
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let startupError {
                ContentUnavailableView {
                    Label("无法启动", systemImage: "externaldrive.badge.xmark")
                } description: {
                    Text(startupError)
                }
            } else {
                appContent
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard startupError == nil else { return }
            await viewModel.start(in: modelContext)
        }
        .alert("提示", isPresented: alertPresented) {
            Button("好") {
                viewModel.alertMessage = nil
            }
        } message: {
            Text(viewModel.alertMessage ?? "发生未知错误。")
        }
    }

    private var appContent: some View {
        TabView(selection: $viewModel.selectedTab) {
            DiscoverView(viewModel: viewModel)
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .tabItem {
                    Label(
                        AppTab.discover.title,
                        systemImage: AppTab.discover.systemImage
                    )
                }
                .tag(AppTab.discover)

            LibraryView(status: .wantToWatch, viewModel: viewModel)
                .tabItem {
                    Label(
                        AppTab.wantToWatch.title,
                        systemImage: AppTab.wantToWatch.systemImage
                    )
                }
                .tag(AppTab.wantToWatch)

            LibraryView(status: .watched, viewModel: viewModel)
                .tabItem {
                    Label(
                        AppTab.watched.title,
                        systemImage: AppTab.watched.systemImage
                    )
                }
                .tag(AppTab.watched)
        }
        .tint(.white)
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.alertMessage = nil } }
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(
                for: [LibraryItem.self, SkippedItem.self],
                inMemory: true
            )
    }
}
