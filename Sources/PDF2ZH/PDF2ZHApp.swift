import SwiftUI
import AppKit

@main
@available(macOS 13.0, *)
struct PDF2ZHApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 564)
                .onAppear {
                    if let window = NSApplication.shared.windows.first {
                        window.level = .normal
                    }
                }
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
} 