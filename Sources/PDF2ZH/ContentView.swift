import SwiftUI

@available(macOS 13.0, *)
struct ContentView: View {
    @StateObject private var processor = PDFProcessor()
    @State private var showFilePicker = false
    @State private var windowHeight: CGFloat = 600
    @State private var isOutputVisible = false
    @State private var selectedSidebarItem: SidebarItem = .options
    @State private var selectedSourceLanguage: Language = .english
    @State private var selectedTargetLanguage: Language = .chinese
    @State private var selectedService: Service = .google
    
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
    
    enum Service: String, CaseIterable, Identifiable {
        case google = "Google"
        case deepl = "DeepL"
        
        var id: String { self.rawValue }
        
        var code: String {
            switch self {
            case .google: return "google"
            case .deepl: return "deepl"
            }
        }
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
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                
                // Button(action: { showFilePicker = true }) {
                //     HStack {
                //         Image(systemName: "plus.circle.fill")
                //             .foregroundColor(.accentColor)
                //         Text("Import a new file...")
                //             .foregroundColor(.secondary)
                //     }
                // }
                //     .buttonStyle(.borderedProminent)
                //     .padding(.vertical, 8)
                Section("Recent Files") {
                    if processor.recentFiles.isEmpty {
                        Text("No recent outputs")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(processor.recentFiles) { file in
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
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Open bilingual version")
                                
                                // Mono icon button
                                Button(action: {
                                    let monoPath = file.url.path.replacingOccurrences(of: "-dual.pdf", with: "-mono.pdf")
                                    let monoURL = URL(fileURLWithPath: monoPath)
                                    NSWorkspace.shared.open(monoURL)
                                }) {
                                    Image(systemName: "doc.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Open mono version")
                            }
                            .padding(.leading, 12)
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(.top, 8)
                
                Section ("Preferences") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Use", selection: $selectedService) {
                            ForEach(Service.allCases) { service in
                                Text(service.rawValue).tag(service)
                            }
                        }
                            .foregroundColor(.secondary)
                        .pickerStyle(.menu)
                    }
                    .padding(.leading,12)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("From", selection: $selectedSourceLanguage) {
                            ForEach(Language.allCases) { language in
                                Text(language.rawValue).tag(language)
                            }
                        }
                            .foregroundColor(.secondary)
                        .pickerStyle(.menu)
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
                    }
                    .padding(.leading,12)
                }
                .padding(.leading, 0)
// add left padding
                
                Section("Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Test version (alpha)")
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 16)
                }
                .padding(.leading, 0)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            // Detail view (main content area)
            VStack(spacing: 24) {
                if !processor.checkPDF2ZH() {
                    VStack {
                        Text("pdf2zh is not installed")
                            .font(.headline)
                        Button("Install PDFMath Translate (alpha)") {
                            processor.openGitHub()
                        }
                    }
                    .padding(24)
                } else {
                    switch selectedSidebarItem {
                    case .service:
                        optionsView
                    case .options:
                        optionsView
                    case .information:
                        informationView
                    }
                }
            }
            .padding(.horizontal, 32)
            .frame(minHeight: calculateWindowHeight())
            .navigationTitle("PDFMath Translate")
            .toolbar {
                if processor.isProcessing {
                    ToolbarItem(placement: .automatic) {
                        HStack(spacing: 8) {
                            ProgressView(value: processor.progress)
                                .progressViewStyle(.linear)
                                .frame(width: 100)
                            
                            Text("\(Int(processor.progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if !processor.estimatedTimeRemaining.isEmpty {
                                Text("ETA: \(processor.estimatedTimeRemaining)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Button(action: {
                                processor.stopProcessing()
                                processor.reset()
                            }) {
                                Image(systemName: "stop.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .help("Stop processing")
                        }
                    }
                }
            }
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
            updateWindowSize()
        }
        .onChange(of: isOutputVisible) { _ in
            updateWindowSize()
        }
        .animation(.easeInOut, value: processor.isProcessing)
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
    
    @ViewBuilder
    var optionsView: some View {
        VStack(spacing: 24) {
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
            }
            
            // PDF Preview Section - show when we have a preview URL
            if let previewURL = processor.outputPreviewURL ?? processor.inputPreviewURL {
                VStack(spacing: 24) {
                    PDFPreviewView(url: previewURL, title: "")
                }
            }
            
            // Output text section - controlled by showOutput
            if processor.showOutput && !processor.outputText.contains("Processing completed successfully!") {
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
                            Text(processor.outputText)
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
    }
    
    @ViewBuilder
    var informationView: some View {
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
                
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func updateWindowSize() {
        if let window = NSApplication.shared.windows.first {
            let newHeight = calculateWindowHeight()
            let newSize = NSSize(width: window.frame.width, height: newHeight)
            window.setContentSize(newSize)
        }
    }
} 