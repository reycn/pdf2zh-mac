import SwiftUI
import Combine // Import Combine for sink if needed later, though didSet is simpler here
import UniformTypeIdentifiers

// Define translation service enum
enum Service: String, CaseIterable, Identifiable {
    case google = "Google"
    case deeplx = "DeepLX"
    case openai = "OpenAI"
    case openaialike = "OpenAI-alike"
    // Add more services as needed
    var id: Self { self }
}

// Map Service enum to CLI service argument
extension Service {
    var cliArgument: String {
        switch self {
        case .google: return "google"
        case .deeplx: return "deeplx"
        case .openai: return "openai"
        case .openaialike: return "openailiked"
        }
    }
}

// Define languages enum
enum Language: String, CaseIterable, Identifiable {
    case english = "English"
    case chinese = "Chinese"
    case french = "French"
    case spanish = "Spanish"
    case german = "German"
    case italian = "Italian"
    case japanese = "Japanese"
    case korean = "Korean"
    case portuguese = "Portuguese"
    case russian = "Russian"
    // Add more languages as needed
    var id: Self { self }
}

// Map Language enum to CLI language codes
extension Language {
    var cliCode: String {
        switch self {
        case .english: return "en"
        case .chinese: return "zh"
        case .french: return "fr"
        case .spanish: return "es"
        case .german: return "de"
        case .italian: return "it"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .portuguese: return "pt"
        case .russian: return "ru"
        }
    }
}

// New struct to represent a recent processed file
struct RecentFile: Identifiable, Codable { // Make Codable
    var id = UUID() // Change let to var
    let name: String
    let dualURL: URL
    let monoURL: URL
}

class AppState: ObservableObject {
    // UserDefaults Keys
    private let serviceKey = "selectedService"
    private let sourceLangKey = "selectedSourceLanguage"
    private let targetLangKey = "selectedTargetLanguage"
    private let autoOpenKey = "autoOpenMono"
    private let recentFilesKey = "recentFiles"
    private let threadsKey = "multiThreads"
    private let compatModeKey = "compatibilityMode"
    private let babeldocKey = "babeldoc"
    private let promptPathKey = "promptPath"
    private let ignoreCacheKey = "ignoreCache"

    @Published var filePath: URL? = nil
    @Published var succeededFilePath: URL? = nil
    @Published var processOutput: String = ""
    @Published var showGuidance: Bool = false
    @Published var progress: Double? = nil
    @Published var currentProcess: Process? = nil
    @Published var dualFilePath: URL? = nil
    @Published var monoFilePath: URL? = nil

    @Published var selectedService: Service {
        didSet {
            UserDefaults.standard.set(selectedService.rawValue, forKey: serviceKey)
        }
    }
    @Published var selectedSourceLanguage: Language {
        didSet {
            UserDefaults.standard.set(selectedSourceLanguage.rawValue, forKey: sourceLangKey)
        }
    }
    @Published var selectedTargetLanguage: Language {
        didSet {
            UserDefaults.standard.set(selectedTargetLanguage.rawValue, forKey: targetLangKey)
        }
    }
    @Published var autoOpenMono: Bool {
        didSet {
            UserDefaults.standard.set(autoOpenMono, forKey: autoOpenKey)
        }
    }
    // New list of recent processed files
    @Published var recentFiles: [RecentFile] {
        didSet {
            // Limit the number of recent files stored
            let limitedRecents = Array(recentFiles.prefix(10))
            if recentFiles.count > limitedRecents.count {
                recentFiles = limitedRecents // Update the published property if it was trimmed
            }
            if let encoded = try? JSONEncoder().encode(limitedRecents) {
                UserDefaults.standard.set(encoded, forKey: recentFilesKey)
            }
        }
    }

    // New advanced options
    @Published var multiThreads: Int {
        didSet { UserDefaults.standard.set(multiThreads, forKey: threadsKey) }
    }
    @Published var compatibilityMode: Bool {
        didSet { UserDefaults.standard.set(compatibilityMode, forKey: compatModeKey) }
    }
    @Published var babeldoc: Bool {
        didSet { UserDefaults.standard.set(babeldoc, forKey: babeldocKey) }
    }
    @Published var promptPath: String? {
        didSet { UserDefaults.standard.set(promptPath, forKey: promptPathKey) }
    }
    @Published var ignoreCache: Bool {
        didSet { UserDefaults.standard.set(ignoreCache, forKey: ignoreCacheKey) }
    }

    init() {
        // Load saved values or use defaults
        let defaults = UserDefaults.standard
        selectedService = Service(rawValue: defaults.string(forKey: serviceKey) ?? Service.deeplx.rawValue) ?? .deeplx
        selectedSourceLanguage = Language(rawValue: defaults.string(forKey: sourceLangKey) ?? Language.english.rawValue) ?? .english
        selectedTargetLanguage = Language(rawValue: defaults.string(forKey: targetLangKey) ?? Language.chinese.rawValue) ?? .chinese
        autoOpenMono = defaults.object(forKey: autoOpenKey) as? Bool ?? true

        // Always initialize advanced options before any return
        multiThreads = defaults.object(forKey: threadsKey) as? Int ?? 1
        compatibilityMode = defaults.object(forKey: compatModeKey) as? Bool ?? false
        babeldoc = defaults.object(forKey: babeldocKey) as? Bool ?? false
        promptPath = defaults.string(forKey: promptPathKey)
        ignoreCache = defaults.object(forKey: ignoreCacheKey) as? Bool ?? false

        // Now load recents
        if let savedRecents = defaults.data(forKey: recentFilesKey) {
            if let decodedRecents = try? JSONDecoder().decode([RecentFile].self, from: savedRecents) {
                recentFiles = decodedRecents
                return // Exit init if loaded successfully
            }
        }
        // Default if no saved data or decoding failed
        recentFiles = []
    }

    // Helper to show prompt file picker
    @MainActor
    func pickPromptFile(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select Prompt File"
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        } else {
            completion(nil)
        }
    }
}

struct MainView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @StateObject private var appState = AppState()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .environmentObject(appState)
        } detail: {
            ContentView()
                .environmentObject(appState)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

@main
struct PDFMathTranslateApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(HiddenTitleBarWindowStyle()) // Hide the window title bar
    }
}