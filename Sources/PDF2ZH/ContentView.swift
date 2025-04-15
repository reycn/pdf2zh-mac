import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Enums
@available(macOS 13.0, *)
enum SidebarItem: String, CaseIterable, Identifiable {
    case service = "Service"
    case options = "Options"
    case information = "Information"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .service: return "globe"
        case .options: return "gear"
        case .information: return "info.circle"
        }
    }
}

@available(macOS 13.0, *)
enum Language: String, CaseIterable, Identifiable {
    case english = "English"
    case chinese = "Chinese"
    case japanese = "Japanese"
    case korean = "Korean"
    case french = "French"
    case german = "German"
    case spanish = "Spanish"
    case russian = "Russian"
    
    var id: String { self.rawValue }
    
    var code: String {
        switch self {
        case .english: return "en"
        case .chinese: return "zh"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .german: return "de"
        case .spanish: return "es"
        case .russian: return "ru"
        }
    }
}

@available(macOS 13.0, *)
enum Service: String, CaseIterable, Identifiable {
    case deeplx = "DeepL X"
    case deepl = "DeepL"
    case google = "Google"
    
    var id: String { self.rawValue }
    
    var code: String {
        switch self {
        case .google: return "google"
        case .deepl: return "deepl"
        case .deeplx: return "deeplx"
        }
    }
}

@available(macOS 13.0, *)
struct ContentView: View {
    @StateObject var processor = PDFProcessor()
    @State private var showFilePicker = false
    @State private var windowHeight: CGFloat = 600
    @State private var isOutputVisible = false
    @State private var selectedSidebarItem: SidebarItem = .options
    @State private var selectedSourceLanguage: Language = .english
    @State private var selectedTargetLanguage: Language = .chinese
    @State private var selectedService: Service = .deeplx
    
    private func calculateWindowHeight() -> CGFloat {
        var height: CGFloat = 64 // Base padding (32 * 2 for top and bottom)
        
        // File drop view or preview height
        if processor.selectedFile == nil {
            height += 400 // FileDropView height
        } else {
            height += 500 // PDF preview height
        }
        
        // Progress bar height
        if processor.isProcessing {
            height += 50
        }
        
        // Output text height
        if processor.showOutput && !processor.outputText.contains("Processing completed successfully!") && isOutputVisible {
            height += 260 // 200 for content + 20 for padding
        }
        
        return height
    }
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                processor: processor,
                selectedSidebarItem: $selectedSidebarItem,
                selectedService: $selectedService,
                selectedSourceLanguage: $selectedSourceLanguage,
                selectedTargetLanguage: $selectedTargetLanguage
            )
        } detail: {
            DetailView(
                processor: processor,
                selectedSidebarItem: selectedSidebarItem,
                showFilePicker: $showFilePicker,
                isOutputVisible: $isOutputVisible,
                updateWindowSize: updateWindowSize
            )
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .onChange(of: processor.isProcessing) { _ in
            updateWindowSize()
        }
        .onChange(of: processor.showOutput) { _ in
            updateWindowSize()
        }
        .onChange(of: processor.outputFile) { _ in
            updateWindowSize()
        }
        .onChange(of: processor.selectedFile) { _ in
            // Ensure window size updates on main thread after state change
            Task { @MainActor in 
                updateWindowSize()
            }
        }
        .onChange(of: isOutputVisible) { _ in
            updateWindowSize()
        }
        .onChange(of: selectedService) { newValue in
            processor.service = newValue
        }
        .onChange(of: selectedSourceLanguage) { newValue in
            processor.sourceLanguage = newValue
        }
        .onChange(of: selectedTargetLanguage) { newValue in
            processor.targetLanguage = newValue
        }
        .animation(.easeInOut, value: processor.isProcessing)
        .toolbar {
            ToolbarView(processor: processor)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    processor.selectedFile = url
                    processor.processPDF()
                }
            case .failure(let error):
                processor.outputText = "Error selecting file: \(error.localizedDescription)\n"
                processor.showOutput = true
            }
        }
    }
    
    @MainActor // Ensure this runs on the main actor
    private func updateWindowSize() {
        if let window = NSApplication.shared.windows.first {
            // Use self to access calculateWindowHeight
            let newHeight = self.calculateWindowHeight()
            let newSize = NSSize(width: window.frame.width, height: newHeight)
            window.setContentSize(newSize)
        }
    }
}

// MARK: - Sidebar View
@available(macOS 13.0, *)
struct SidebarView: View {
    let processor: PDFProcessor
    @Binding var selectedSidebarItem: SidebarItem
    @Binding var selectedService: Service
    @Binding var selectedSourceLanguage: Language
    @Binding var selectedTargetLanguage: Language
    
    var body: some View {
        List {
            Section {
                if processor.recentFiles.isEmpty {
                    Text("No recent outputs")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(processor.recentFiles) { file in
                        RecentFileRow(file: file, processor: processor)
                    }
                }
            } header: {
                Text("Recent Files")
            }
            .padding(.top, 8)
            
            Section {
                PreferencesView(
                    selectedService: $selectedService,
                    selectedSourceLanguage: $selectedSourceLanguage,
                    selectedTargetLanguage: $selectedTargetLanguage,
                    processor: processor
                )
            } header: {
                Text("Preferences")
            }
            .padding(.leading, 0)
            .padding(.top, 8)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .animation(.easeInOut(duration: 0.1), value: selectedSidebarItem)
    }
}

// MARK: - Recent File Row
@available(macOS 13.0, *)
struct RecentFileRow: View {
    let file: PDFProcessor.RecentFile
    let processor: PDFProcessor
    @State private var isBilingualHovered = false
    @State private var isMonoHovered = false
    @State private var isNewItem = true
    
    var body: some View {
        HStack(spacing: 8) {
            // File name button (opens bilingual)
            Button(action: {
                processor.openRecentFile(file)
            }) {
                Text(file.name)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Bilingual icon button
            Button(action: {
                processor.openRecentFile(file)
            }) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(isBilingualHovered ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Open bilingual version")
            .onHover { isHovered in
                isBilingualHovered = isHovered
            }
            
            // Mono icon button
            Button(action: {
                let monoPath = file.url.path.replacingOccurrences(of: "-dual.pdf", with: "-mono.pdf")
                let monoURL = URL(fileURLWithPath: monoPath)
                NSWorkspace.shared.open(monoURL)
            }) {
                Image(systemName: "doc.fill")
                    .foregroundColor(isMonoHovered ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Open mono version")
            .onHover { isHovered in
                isMonoHovered = isHovered
            }
        }
        .padding(.leading, 12)
        .cornerRadius(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isNewItem ? 0.1 : 0))
        )
        .onAppear {
            // Animate twice
            withAnimation(.easeInOut(duration: 0.5).repeatCount(2)) {
                isNewItem = false
            }
        }
    }
}

// MARK: - Preferences View
@available(macOS 13.0, *)
struct PreferencesView: View {
    @Binding var selectedService: Service
    @Binding var selectedSourceLanguage: Language
    @Binding var selectedTargetLanguage: Language
    let processor: PDFProcessor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Use", selection: $selectedService) {
                    ForEach(Service.allCases) { service in
                        Text(service.rawValue).tag(service)
                    }
                }
                .foregroundColor(.secondary)
                .pickerStyle(.menu)
                .onChange(of: selectedService) { newValue in
                    processor.service = newValue
                }
            }
            .padding(.leading, 12)
            
            VStack(alignment: .leading, spacing: 8) {
                Picker("From", selection: $selectedSourceLanguage) {
                    ForEach(Language.allCases) { language in
                        Text(language.rawValue).tag(language)
                    }
                }
                .foregroundColor(.secondary)
                .pickerStyle(.menu)
                .onChange(of: selectedSourceLanguage) { newValue in
                    processor.sourceLanguage = newValue
                }
            }
            .padding(.leading, 12)
            
            VStack(alignment: .leading, spacing: 8) {
                Picker("To", selection: $selectedTargetLanguage) {
                    ForEach(Language.allCases) { language in
                        Text(language.rawValue).tag(language)
                    }
                }
                .foregroundColor(.secondary)
                .pickerStyle(.menu)
                .onChange(of: selectedTargetLanguage) { newValue in
                    processor.targetLanguage = newValue
                }
            }
            .padding(.leading, 12)
        }
    }
}

// MARK: - Detail View
@available(macOS 13.0, *)
struct DetailView: View {
    let processor: PDFProcessor
    let selectedSidebarItem: SidebarItem
    @Binding var showFilePicker: Bool
    @Binding var isOutputVisible: Bool
    let updateWindowSize: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            if !processor.checkPDF2ZH() {
                VStack {
                    Text("pdf2zh is not installed")
                        .font(.headline)
                    Button("Install PDFMath Translate (alpha)") {
                        // Removed GitHub button action
                    }
                }
                .padding(24)
            } else {
                switch selectedSidebarItem {
                case .service:
                    ContentOptionsView(
                        processor: processor,
                        showFilePicker: $showFilePicker,
                        isOutputVisible: $isOutputVisible,
                        updateWindowSize: updateWindowSize
                    )
                case .options:
                    ContentOptionsView(
                        processor: processor,
                        showFilePicker: $showFilePicker,
                        isOutputVisible: $isOutputVisible,
                        updateWindowSize: updateWindowSize
                    )
                case .information:
                    InformationView()
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(minHeight: calculateWindowHeight())
        .navigationTitle("PDFMath Translate")
    }
    
    private func calculateWindowHeight() -> CGFloat {
        var height: CGFloat = 64 // Base padding (32 * 2 for top and bottom)
        
        // File drop view or preview height
        if processor.selectedFile == nil {
            height += 400 // FileDropView height
        } else {
            height += 500 // PDF preview height
        }
        
        // Progress bar height
        if processor.isProcessing {
            height += 50
        }
        
        // Output text height
        if processor.showOutput && !processor.outputText.contains("Processing completed successfully!") && isOutputVisible {
            height += 260 // 200 for content + 20 for padding
        }
        
        return height
    }
}

// MARK: - Toolbar View
@available(macOS 13.0, *)
struct ToolbarView: ToolbarContent {
    @ObservedObject var processor: PDFProcessor
    
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            // let _ = print("[ToolbarView] State - isProcessing: \(processor.isProcessing), selectedFile: \(processor.selectedFile != nil), outputFile: \(processor.outputFile != nil)") // Removed debug print
            
            if processor.isProcessing {
                // State 1: Actively processing
                // let _ = print("[ToolbarView] Showing ProcessingToolbarView") // Removed debug print
                ProcessingToolbarView(processor: processor)
            } else if processor.outputFile != nil {
                // State 2: Processing finished successfully
                // let _ = print("[ToolbarView] Showing Success State") // Removed debug print
                HStack(spacing: 12) {
                    Text("Succeed")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Button(action: {
                        processor.reset()
                    }) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Start Over")
                    
                    Button(action: {
                        if let outputFile = processor.outputFile {
                            let monoPath = outputFile.path.replacingOccurrences(of: "-dual.pdf", with: "-mono.pdf")
                            let monoURL = URL(fileURLWithPath: monoPath)
                            NSWorkspace.shared.open(monoURL)
                        }
                    }) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Open mono version")
                }
            } else {

                Text("Version 0.0.1")
                .padding(.trailing, 8)
                // State 3: Initial state or processing stopped/failed
                // let _ = print("[ToolbarView] Showing GitHub Button") // Removed debug print
                Button(action: { processor.openGitHub() }) {
                    HStack(spacing: 4) {
                        if let imagePath = Bundle.module.path(forResource: "github-mark", ofType: "png"),
                           let image = NSImage(contentsOfFile: imagePath) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                        }
                        Text("GitHub")
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Processing Toolbar View
@available(macOS 13.0, *)
struct ProcessingToolbarView: View {
    let processor: PDFProcessor
    
    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: processor.progress)
                .progressViewStyle(.linear)
                .frame(width: 150)
                .tint(.blue)
            
            Text("\(Int(processor.progress * 100))%")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.primary)
                .frame(width: 50)
            
            if !processor.estimatedTimeRemaining.isEmpty {
                Text("ETA: \(processor.estimatedTimeRemaining)")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 100)
            }
            
            Button(action: {
                processor.stopProcessing()
                processor.reset()
            }) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Stop processing")
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Content Options View
@available(macOS 13.0, *)
struct ContentOptionsView: View {
    @ObservedObject var processor: PDFProcessor
    @Binding var showFilePicker: Bool
    @Binding var isOutputVisible: Bool
    let updateWindowSize: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Conditional rendering: Only include FileDropView if no file is selected
            if processor.selectedFile == nil {
                FileDropView(showFilePicker: $showFilePicker, processor: processor)
                    .onAppear {
                        // Reset window size to initial state when file selection view appears
                        if let window = NSApplication.shared.windows.first {
                            let initialHeight: CGFloat = 564 // Base padding + FileDropView height
                            let newSize = NSSize(width: window.frame.width, height: initialHeight)
                            window.setContentSize(newSize)
                        }
                    }
            } else {
                // PDF Preview Section - show when we have a preview URL
                if let previewURL = processor.outputPreviewURL ?? processor.inputPreviewURL {
                    VStack(spacing: 24) {
                        PDFPreviewView(url: previewURL, title: "")
                            .id(previewURL) // Keep id modifier to force recreation on URL change
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // Optionally show a placeholder or error message if needed when selectedFile is not nil but no preview URL is ready
                    Text("Preparing preview...")
                        .foregroundColor(.secondary)
                        .frame(height: 500) // Match preview height
                }
            }
            
            // Output text section - controlled by showOutput
            if processor.showOutput && !processor.outputText.contains("Processing completed successfully!") {
                OutputTextView(
                    isOutputVisible: $isOutputVisible,
                    outputText: processor.outputText
                )
            }
        }
    }
}

// MARK: - Output Text View
@available(macOS 13.0, *)
struct OutputTextView: View {
    @Binding var isOutputVisible: Bool
    let outputText: String
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: {
                withAnimation {
                    isOutputVisible.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isOutputVisible ? "chevron.down" : "chevron.right")
                    Text("Command Line Output")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            if isOutputVisible {
                ScrollView {
                    Text(outputText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(height: 200)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

// PDFPreviewView and PDFKitView are defined in PDFPreviewView.swift

// MARK: - Information View
@available(macOS 13.0, *)
struct InformationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                Text("About")
                    .font(.headline)
                
                Text("PDF2ZH is a macOS application that helps you translate PDFs with mathematical content. It uses the pdf2zh command-line utility to process PDFs and translate them into simplified Chinese.")
                    .padding(.bottom, 8)
                
                Text("Usage")
                    .font(.headline)
                
                Text("1. Select a PDF file by dropping it into the app or using the file picker.")
                Text("2. Wait for the processing to complete.")
                Text("3. View and save the translated output files.")
                    .padding(.bottom, 8)
                
                Text("Requirements")
                    .font(.headline)
                
                Text("• macOS 13.0 or later")
                Text("• pdf2zh command-line utility installed")
                    .padding(.bottom, 8)
                
                Text("Website")
                    .font(.headline)
                
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
} 