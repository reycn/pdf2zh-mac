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
    @Published var progress: Double = 0.0 {
        didSet {
            if progress >= 1.0 {
                Task { @MainActor in
                    if let window = NSApplication.shared.windows.first {
                        let newHeight = calculateWindowHeight()
                        let newSize = NSSize(width: window.frame.width, height: newHeight)
                        window.setContentSize(newSize)
                    }
                }
            }
        }
    }
    @Published var progressText: String = ""
    @Published var showOutput: Bool = false
    @Published var estimatedTimeRemaining: String = ""
    @Published var recentFiles: [RecentFile] = []
    
    private let queue = DispatchQueue(label: "com.pdf2zh.processor", qos: .userInitiated)
    private var startTime: Date?
    private var lastProgressUpdate: Date?
    private let maxRecentFiles = 5
    private let recentFilesKey = "com.pdf2zh.recentFiles"
    private var process: Process?
    
    struct RecentFile: Identifiable, Equatable, Codable {
        let id: UUID
        let name: String
        let url: URL
        let date: Date
        
        static func == (lhs: RecentFile, rhs: RecentFile) -> Bool {
            return lhs.url == rhs.url
        }
        
        enum CodingKeys: String, CodingKey {
            case id, name, url, date
        }
        
        init(name: String, url: URL, date: Date) {
            self.id = UUID()
            self.name = name
            self.url = url
            self.date = date
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            let urlString = try container.decode(String.self, forKey: .url)
            guard let url = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(forKey: .url, in: container, debugDescription: "Invalid URL string")
            }
            self.url = url
            date = try container.decode(Date.self, forKey: .date)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(url.absoluteString, forKey: .url)
            try container.encode(date, forKey: .date)
        }
    }
    
    init() {
        loadRecentFiles()
    }
    
    private func loadRecentFiles() {
        if let data = UserDefaults.standard.data(forKey: recentFilesKey),
           let decoded = try? JSONDecoder().decode([RecentFile].self, from: data) {
            recentFiles = decoded
        }
    }
    
    private func saveRecentFiles() {
        if let encoded = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(encoded, forKey: recentFilesKey)
        }
    }
    
    private func addToRecentFiles(_ url: URL) {
        let fileName = url.lastPathComponent
        let newFile = RecentFile(name: fileName, url: url, date: Date())
        
        // Remove if already exists
        recentFiles.removeAll { $0.url == url }
        
        // Add to the beginning
        recentFiles.insert(newFile, at: 0)
        
        // Limit the number of recent files
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
        
        saveRecentFiles()
    }
    
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
    
    func stopProcessing() {
        queue.sync {
            if let process = process {
                process.terminate()
                self.process = nil
            }
            isProcessing = false
            progress = 0.0
            progressText = ""
            outputText = ""
            showOutput = false
            estimatedTimeRemaining = ""
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
        
        process = Process()
        process?.launchPath = "/bin/zsh"
        // Properly escape paths and use single quotes for better shell compatibility
        process?.arguments = ["-c", "pdf2zh '\(filePath.replacingOccurrences(of: "'", with: "'\\''"))' -o '\(fileDir.replacingOccurrences(of: "'", with: "'\\''"))'"]
        
        let pipe = Pipe()
        process?.standardOutput = pipe
        process?.standardError = pipe
        
        let outputHandle = pipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] pipe in
            guard let self = self else { return }
            
            // Read all available data
            let data = pipe.availableData
            if data.isEmpty {
                return
            }
            
            // Convert data to string, handling potential encoding issues
            if let line = String(data: data, encoding: .utf8) {
                // Process each line separately
                let lines = line.components(separatedBy: .newlines)
                for line in lines {
                    if line.isEmpty {
                        continue
                    }
                    
                    print("Processing line: \(line)")
                    
                    Task { @MainActor in
                        self.queue.sync {
                            // Check for success message in the output
                            if line.contains("Processing completed successfully!") {
                                self.outputText += "[Success] \(line)\n"
                                self.showOutput = true
                                self.progress = 1.0
                                self.progressText = "Completed"
                                self.isProcessing = false
                                
                                // Set output file and preview immediately
                                let outputPath = "\(fileDir)/\(outputFileName)"
                                self.outputFile = URL(fileURLWithPath: outputPath)
                                self.outputPreviewURL = self.outputFile
                                
                                // Add to recent files
                                self.addToRecentFiles(self.outputFile!)
                                return
                            }
                            
                            if self.shouldShowOutput(line) {
                                self.outputText += self.formatOutputLine(line) + "\n"
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
        }
        
        process?.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self = self else { return }
                self.queue.sync {
                    self.isProcessing = false
                    if process.terminationStatus == 0 {
                        let outputPath = "\(fileDir)/\(outputFileName)"
                        self.outputFile = URL(fileURLWithPath: outputPath)
                        self.outputPreviewURL = self.outputFile
                        
                        // Add to recent files
                        self.addToRecentFiles(self.outputFile!)
                        
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
            try process?.run()
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
    
    func openRecentFile(_ file: RecentFile) {
        NSWorkspace.shared.open(file.url)
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
    
    private func calculateWindowHeight() -> CGFloat {
        var height: CGFloat = 64 // Base padding
        
        // PDF preview height
        if outputPreviewURL != nil {
            height += 400
        }
        
        // Output buttons height
        if outputFile != nil {
            height += 160
        }
        
        return height
    }
} 
 