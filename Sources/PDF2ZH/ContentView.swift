import SwiftUI

@available(macOS 13.0, *)
struct ContentView: View {
    @StateObject private var processor = PDFProcessor()
    @State private var showFilePicker = false
    @State private var windowHeight: CGFloat = 600
    @State private var isOutputVisible = false
    
    private func calculateWindowHeight() -> CGFloat {
        var height: CGFloat = 64 // Base padding (32 * 2 for top and bottom)
        
        // File drop view or preview height
        if processor.selectedFile == nil {
            height += 400 // FileDropView height
        } else {
            height += 400 // PDF preview height
        }
        
        // Progress bar height
        if processor.isProcessing {
            height += 50
        }
        
        // Output text height
        if processor.showOutput && !processor.outputText.contains("Processing completed successfully!") && isOutputVisible {
            height += 260 // 200 for content + 20 for padding
        }
        
        // Output buttons height
        if processor.outputFile != nil {
            height += 160
        }
        
        return height
    }
    
    var body: some View {
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
                
                // Progress bar section - always show when processing
                if processor.isProcessing {
                    ProgressView(value: processor.progress) {
                        HStack {
                            Text("Processing: \(processor.progressText)")
                                .font(.caption)
                            Spacer()
                            HStack(spacing: 4) {
                                if !processor.estimatedTimeRemaining.isEmpty {
                                    Text("ETA: \(processor.estimatedTimeRemaining)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text("\(Int(processor.progress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 0)
                    .animation(.easeInOut, value: processor.progress)
                    .transition(.opacity)
                }
                
                // PDF Preview Section
                if processor.selectedFile != nil {
                    if processor.outputPreviewURL != nil {
                        // Show output preview after processing
                        VStack(spacing: 24) {
                            PDFPreviewView(url: processor.outputPreviewURL, title: "Translated PDF")
                            
                            VStack(spacing: 16) {
                                HStack(spacing: 8) {
                                    Button(action: {
                                        processor.openOutputFile()
                                    }) {
                                        HStack {
                                            Image(systemName: "doc.fill")
                                            Text("Open Output File (dual)")
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(processor.isProcessing)
                                    
                                    Button(action: {
                                        if let outputFile = processor.outputFile {
                                            let monoPath = outputFile.path.replacingOccurrences(of: "-dual.pdf", with: "-mono.pdf")
                                            let monoURL = URL(fileURLWithPath: monoPath)
                                            NSWorkspace.shared.open(monoURL)
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "doc.fill")
                                            Text("Open Output File (mono)")
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(processor.isProcessing)
                                }
                                
                                Button(action: {
                                    isOutputVisible = false
                                    processor.reset()
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Initiate another task")
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.top, 24)
                    } else {
                        // Show input preview before processing
                        PDFPreviewView(url: processor.inputPreviewURL, title: "Original PDF")
                            .padding(.top, 24)
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
                    .padding(.horizontal, 24)
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(minWidth: 800, minHeight: calculateWindowHeight())
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
    
    private func updateWindowSize() {
        if let window = NSApplication.shared.windows.first {
            let newHeight = calculateWindowHeight()
            let newSize = NSSize(width: window.frame.width, height: newHeight)
            window.setContentSize(newSize)
        }
    }
} 