import SwiftUI
import AppKit

@main
@available(macOS 13.0, *)
struct PDF2ZHApp: App {
    @StateObject var processor = PDFProcessor()
    
    init() {
        // Check if we're running as a proper app bundle
        if Bundle.main.bundleIdentifier == nil {
            print("Warning: Not running as a proper app bundle. Some features may be disabled.")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 564)
                .onAppear {
                    if let window = NSApplication.shared.windows.first {
                        window.level = .normal
                    }
                }
                .environmentObject(processor)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
} 
