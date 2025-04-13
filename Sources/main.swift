// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI
import Foundation
import ArgumentParser
import UniformTypeIdentifiers

@available(macOS 13.0, *)
struct FileDropView: View {
    @Binding var showFilePicker: Bool
    @ObservedObject var processor: PDFProcessor
    @State private var isTargeted = false
    
    var body: some View {
        VStack(spacing: 32) {
            Button(action: { showFilePicker = true }) {
                HStack {
                    Image(systemName: "doc.fill")
                    Text("Select PDF File")
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(processor.isProcessing)
            
            Text("or")
                .foregroundColor(.secondary)
            
            Text("Drag and drop PDF file here")
                .padding()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTargeted ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isTargeted ? Color.blue : Color.gray, style: StrokeStyle(lineWidth: 2, dash: [5]))
                )
                .onDrop(of: [.pdf], isTargeted: $isTargeted) { providers, _ in
                    guard let provider = providers.first else { return false }
                    
                    provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, error in
                        if let url = item as? URL {
                            Task { @MainActor in
                                processor.selectedFile = url
                                processor.processPDF()
                            }
                        }
                    }
                    return true
                }
        }
        .padding()
        .opacity(processor.selectedFile == nil ? 1 : 0)
        .animation(.easeInOut, value: processor.selectedFile)
    }
}

@available(macOS 13.0, *)
final class PDFProcessor: ObservableObject, @unchecked Sendable {
    @Published var outputText: String = ""
    @Published var isProcessing: Bool = false
    @Published var selectedFile: URL?
    @Published var outputFile: URL?
    @Published var progress: Double = 0.0
    @Published var progressText: String = ""
    @Published var showOutput: Bool = false
    @Published var estimatedTimeRemaining: String = ""
    
    private let queue = DispatchQueue(label: "com.pdf2zh.processor", qos: .userInitiated)
    private var startTime: Date?
    private var lastProgressUpdate: Date?
    
    private func parseProgress(from line: String) -> (Double, String, String)? {
        // Try to match percentage pattern first (e.g., "4%", "15%")
        let percentagePattern = #"(\d+)%"#
        if let regex = try? NSRegularExpression(pattern: percentagePattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges >= 2 {
            let percentage = Int((line as NSString).substring(with: match.range(at: 1))) ?? 0
            let progress = Double(percentage) / 100.0
            print("Found percentage progress: \(percentage)%")
            return (progress, "\(percentage)%", "")
        }
        
        // Try to match fraction pattern (e.g., "4/46")
        let fractionPattern = #"(\d+)\s*[/]\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: fractionPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges >= 3 {
            let current = Int((line as NSString).substring(with: match.range(at: 1))) ?? 0
            let total = Int((line as NSString).substring(with: match.range(at: 2))) ?? 0
            if total > 0 {
                let progress = Double(current) / Double(total)
                print("Found fraction progress: \(current)/\(total)")
                return (progress, "\(current)/\(total)", "")
            }
        }
        
        // Try to match progress bar pattern with time (e.g., "| 2/46 [00:01<00:27, 1.621t/s]")
        let progressBarPattern = #"\|?\s*(\d+)\s*/\s*(\d+)\s*\[([^\]]*)\]"#
        if let regex = try? NSRegularExpression(pattern: progressBarPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges >= 4 {
            let current = Int((line as NSString).substring(with: match.range(at: 1))) ?? 0
            let total = Int((line as NSString).substring(with: match.range(at: 2))) ?? 0
            let timeInfo = (line as NSString).substring(with: match.range(at: 3))
            
            if total > 0 {
                let progress = Double(current) / Double(total)
                print("Found progress bar: \(current)/\(total)")
                
                // Extract estimated time remaining from timeInfo
                let timePattern = #"<([^,]+)"#
                if let timeRegex = try? NSRegularExpression(pattern: timePattern),
                   let timeMatch = timeRegex.firstMatch(in: timeInfo, range: NSRange(timeInfo.startIndex..., in: timeInfo)),
                   timeMatch.numberOfRanges >= 2 {
                    let timeRemaining = (timeInfo as NSString).substring(with: timeMatch.range(at: 1))
                    return (progress, "\(current)/\(total)", timeRemaining)
                }
                return (progress, "\(current)/\(total)", "")
            }
        }
        
        return nil
    }
    
    private func shouldShowOutput(_ line: String) -> Bool {
        // Ignore argos-translate warnings
        if line.contains("argos-translate") {
            return false
        }
        
        // Show output if it contains an error or doesn't contain progress information
        let hasProgress = line.contains("%") || line.contains("/") || line.contains("|")
        return line.contains("error") || line.contains("Error") || !hasProgress
    }
    
    func checkPDF2ZH() -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = ["pdf2zh"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    func openGitHub() {
        if let url = URL(string: "https://github.com/byaidu/pdfmathtranslate") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func processPDF() {
        guard let filePath = selectedFile?.path else { return }
        guard let fileURL = selectedFile else { return }
        let fileDir = fileURL.deletingLastPathComponent().path
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let outputFileName = "\(fileName)-dual.pdf"
        
        print("Starting PDF processing...")
        isProcessing = true
        progress = 0.0
        progressText = ""
        outputText = ""
        showOutput = false
        estimatedTimeRemaining = ""
        startTime = Date()
        lastProgressUpdate = nil
        
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-c", "pdf2zh \"\(filePath)\" -o \"\(fileDir)\" "]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        let outputHandle = pipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] pipe in
            if let line = String(data: pipe.availableData, encoding: .utf8) {
                print("Received line: \(line)")
                Task { @MainActor in
                    guard let self = self else { return }
                    self.queue.sync {
                        if self.shouldShowOutput(line) {
                            self.outputText += line
                            self.showOutput = true
                        }
                        if let (newProgress, progressText, timeRemaining) = self.parseProgress(from: line) {
                            print("Updating progress: \(newProgress), text: \(progressText)")
                            self.progress = newProgress
                            self.progressText = progressText
                            if !timeRemaining.isEmpty {
                                self.estimatedTimeRemaining = timeRemaining
                            }
                        }
                    }
                }
            }
        }
        
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self = self else { return }
                self.queue.sync {
                    self.isProcessing = false
                    if process.terminationStatus == 0 {
                        let outputPath = "\(fileDir)/\(outputFileName)"
                        self.outputFile = URL(fileURLWithPath: outputPath)
                        if !self.showOutput {
                            self.outputText = "Processing completed successfully!\n"
                            self.showOutput = true
                        }
                        self.progress = 1.0
                        self.progressText = "Completed"
                    } else {
                        self.outputText += "\nProcessing failed with exit code: \(process.terminationStatus)\n"
                        self.showOutput = true
                    }
                }
            }
        }
        
        do {
            try process.run()
        } catch {
            outputText = "Error: \(error.localizedDescription)\n"
            showOutput = true
            isProcessing = false
        }
    }
    
    func openOutputFile() {
        if let outputFile = outputFile {
            NSWorkspace.shared.open(outputFile)
        }
    }
}

@available(macOS 13.0, *)
struct ContentView: View {
    @StateObject private var processor = PDFProcessor()
    @State private var showFilePicker = false
    
    var body: some View {
        VStack(spacing: 32) {
            if !processor.checkPDF2ZH() {
                VStack {
                    Text("pdf2zh is not installed")
                        .font(.headline)
                    Button("Install PDFMath Translate") {
                        processor.openGitHub()
                    }
                }
                .padding()
            } else {
                if processor.selectedFile == nil {
                    FileDropView(showFilePicker: $showFilePicker, processor: processor)
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
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .animation(.easeInOut, value: processor.progress)
                    .transition(.opacity)
                }
                
                // Output text section - controlled by showOutput
                if processor.showOutput {
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
                
                if processor.outputFile != nil {
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
                        .buttonStyle(.borderedProminent)
                        .disabled(processor.isProcessing)
                    }
                }
            }
        }
        .padding(.horizontal)
        .frame(minWidth: 400, minHeight: 400)
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
}

@main
@available(macOS 13.0, *)
struct PDF2ZHApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, minHeight: 400)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
