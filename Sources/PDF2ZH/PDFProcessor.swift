import SwiftUI
import Foundation

@available(macOS 13.0, *)
final class PDFProcessor: ObservableObject, @unchecked Sendable {
    @Published var outputText: String = ""
    @Published var isProcessing: Bool = false
    @Published var selectedFile: URL?
    @Published var outputFile: URL?
    @Published var inputPreviewURL: URL?
    @Published var outputPreviewURL: URL?
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
    
    private func formatOutputLine(_ line: String) -> String {
        if line.contains("error") || line.contains("Error") {
            return "[Error] \(line)"
        } else if line.contains("warning") || line.contains("Warning") {
            return "[Warning] \(line)"
        } else if line.contains("Processing completed successfully!") {
            return "[Success] \(line)"
        } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[Message] \(line)"
        }
        return line
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
        
        // Set input preview URL
        inputPreviewURL = fileURL
        
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
                            self.outputText += self.formatOutputLine(line)
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
                        self.outputPreviewURL = self.outputFile
                        if !self.showOutput {
                            self.outputText = "[Success] Processing completed successfully!\n"
                            self.showOutput = true
                        }
                        self.progress = 1.0
                        self.progressText = "Completed"
                    } else {
                        self.outputText += "\n[Error] Processing failed with exit code: \(process.terminationStatus)\n"
                        self.showOutput = true
                    }
                }
            }
        }
        
        do {
            try process.run()
        } catch {
            outputText = "[Error] \(error.localizedDescription)\n"
            showOutput = true
            isProcessing = false
        }
    }
    
    func openOutputFile() {
        if let outputFile = outputFile {
            NSWorkspace.shared.open(outputFile)
        }
    }
    
    func reset() {
        outputText = ""
        isProcessing = false
        selectedFile = nil
        outputFile = nil
        inputPreviewURL = nil
        outputPreviewURL = nil
        progress = 0.0
        progressText = ""
        showOutput = false
        estimatedTimeRemaining = ""
    }
} 
 