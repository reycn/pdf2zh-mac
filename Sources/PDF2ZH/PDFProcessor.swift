import SwiftUI
import Foundation
import Combine
import PDFKit
import UserNotifications
import Vision

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
            print("Progress updated to: \(progress)")
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
    @Published var service: Service = .google
    @Published var sourceLanguage: Language = .english
    @Published var targetLanguage: Language = .chinese
    @Published var autoOpenMono: Bool = true
    
    private let queue = DispatchQueue(label: "com.pdf2zh.processor", qos: .userInitiated)
    private var startTime: Date?
    private var lastProgressUpdate: Date?
    private let maxRecentFiles = 5
    private let recentFilesKey = "com.pdf2zh.recentFiles"
    private var process: Process?
    private var outputBuffer = ""
    
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
        // Request notification permission and set delegate on init
        setupNotifications()
    }
    
    private func setupNotifications() {
        // Check if we're running as a proper app bundle
        guard Bundle.main.bundleIdentifier != nil else {
            print("Warning: Not running as a proper app bundle. Notifications disabled.")
            return
        }
        
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error.localizedDescription)")
                return
            }
            if granted {
                print("Notification permission granted. Setting delegate.")
                // Set delegate on main thread directly
                DispatchQueue.main.async { 
                    // Re-fetch center instance inside the main queue block
                    let currentCenter = UNUserNotificationCenter.current()
                    currentCenter.delegate = NotificationDelegate.shared
                }
            } else {
                print("Notification permission denied.")
            }
        }
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
        // Try to match tqdm-style progress bar pattern (e.g., " 4%|▍         | 2/52 [00:00<00:15,  3.27it/s]")
        let tqdmPattern = #"^\s*(\d+)%\s*\|[^|]*\|\s*(\d+)/(\d+)\s*\[([^\]]*)\]"#
        if let regex = try? NSRegularExpression(pattern: tqdmPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges >= 5 {
            let percentage = Int((line as NSString).substring(with: match.range(at: 1))) ?? 0
            let current = Int((line as NSString).substring(with: match.range(at: 2))) ?? 0
            let total = Int((line as NSString).substring(with: match.range(at: 3))) ?? 0
            let timeInfo = (line as NSString).substring(with: match.range(at: 4))
            
            let progress = Double(percentage) / 100.0
            print("Found tqdm progress: \(percentage)% (\(current)/\(total))")
            
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
        
        // Try to match percentage pattern (e.g., "4%", "15%")
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
        
        // Try to match simple progress indicator (e.g., "Processing page 5 of 10")
        let pagePattern = #"Processing page (\d+) of (\d+)"#
        if let regex = try? NSRegularExpression(pattern: pagePattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges >= 3 {
            let current = Int((line as NSString).substring(with: match.range(at: 1))) ?? 0
            let total = Int((line as NSString).substring(with: match.range(at: 2))) ?? 0
            if total > 0 {
                let progress = Double(current) / Double(total)
                print("Found page progress: \(current)/\(total)")
                return (progress, "Page \(current)/\(total)", "")
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
        if let url = URL(string: "https://github.com/reycn/pdf2zh-mac") {
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
        
        Task { @MainActor in
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
            objectWillChange.send()
        }
        
        process = Process()
        process?.launchPath = "/bin/zsh"
        let command = "pdf2zh '\(filePath.replacingOccurrences(of: "'", with: "'\\''"))' -s '\(service.code)' -o '\(fileDir.replacingOccurrences(of: "'", with: "'\\''"))'"
        print("Executing command: \(command)")
        process?.arguments = ["-c", command]
        let pipe = Pipe()
        process?.standardOutput = pipe
        process?.standardError = pipe
        let outputHandle = pipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] pipe in
            guard let self = self else { return }
            let data = pipe.availableData
            if data.isEmpty { return }
            if let chunk = String(data: data, encoding: .utf8) {
                print("Raw output chunk: \(chunk)")
                self.outputBuffer += chunk
                while let range = self.outputBuffer.range(of: "\n") {
                    let line = String(self.outputBuffer[..<range.lowerBound])
                    self.outputBuffer = String(self.outputBuffer[range.upperBound...])
                    if line.isEmpty { continue }
                    
                    print("Processing line: \(line)")
                    
                    // Process the line immediately on the main thread
                    Task { @MainActor in
                        if line.contains("Processing completed successfully!") {
                            print("Found success message")
                            self.outputText += "[Success] \(line)\n"
                            if !self.showOutput { self.showOutput = true }
                        } else if self.shouldShowOutput(line) {
                            print("Showing output line: \(line)")
                            self.outputText += self.formatOutputLine(line) + "\n"
                            self.showOutput = true
                        }
                        
                        // Parse and update progress immediately
                        if let (newProgress, progressText, timeRemaining) = self.parseProgress(from: line) {
                            print("Progress update - value: \(newProgress), text: \(progressText), time: \(timeRemaining)")
                            if self.progress < 1.0 {
                                withAnimation {
                                    self.progress = newProgress
                                    self.progressText = progressText
                                    if !timeRemaining.isEmpty {
                                        self.estimatedTimeRemaining = timeRemaining
                                    }
                                }
                                self.objectWillChange.send()
                            }
                        } else {
                            print("No progress information found in line")
                        }
                    }
                }
            }
        }
        
        process?.terminationHandler = { [weak self] process in
            // Ensure the entire termination handling runs on the MainActor
            Task { @MainActor in
                guard let self = self else { return }
                
                // Final state update
                self.isProcessing = false
                self.estimatedTimeRemaining = "" // Clear ETA
                
                if process.terminationStatus == 0 {
                    // --- Success Case ---
                    let outputPath = "\(fileDir)/\(outputFileName)"
                    let outputFile = URL(fileURLWithPath: outputPath)
                    let monoPath = outputPath.replacingOccurrences(of: "-dual.pdf", with: "-mono.pdf")
                    let monoURL = URL(fileURLWithPath: monoPath)
                    
                    // Set output file and preview URL (mono version)
                    self.outputFile = outputFile // Still keep the dual file as the main output reference
                    self.outputPreviewURL = monoURL // Set preview to the mono file
                    
                    // Update other state
                    self.addToRecentFiles(outputFile)
                    if !self.outputText.contains("[Success]") { // Add success message if not already seen
                       self.outputText += "[Success] Processing completed successfully!\n"
                    }
                    self.showOutput = true // Ensure output is visible
                    self.progress = 1.0
                    self.progressText = "Completed"
                    
                    // Send notification
                    let dualPath = outputFile.path.replacingOccurrences(of: "-mono.pdf", with: "-dual.pdf")
                    let dualURL = URL(fileURLWithPath: dualPath)
                    self.sendNotification(title: "Processing Completed", body: "The PDF processing completed successfully!", url: dualURL)
                    
                    // Update window size *after* setting the outputPreviewURL
                    if let window = NSApplication.shared.windows.first {
                        let newHeight = self.calculateWindowHeight()
                        let newSize = NSSize(width: window.frame.width, height: newHeight)
                        window.setContentSize(newSize)
                    }
                    
                    // Auto-open mono file if enabled
                    if self.autoOpenMono {
                        self.openMonoFile()
                    }
                    
                } else {
                    // --- Error Case ---
                    self.outputText += "\n[Error] Processing failed with exit code: \(process.terminationStatus)\n"
                    self.showOutput = true
                    self.progress = 0.0 // Reset progress on error
                    self.progressText = "Failed"
                    
                    // Send notification
                    self.sendNotification(title: "Processing Error", body: "The PDF processing failed with exit code: \(process.terminationStatus)")
                    
                    // Update window size even on error (might need less space)
                     if let window = NSApplication.shared.windows.first {
                        let newHeight = self.calculateWindowHeight()
                        let newSize = NSSize(width: window.frame.width, height: newHeight)
                        window.setContentSize(newSize)
                    }
                }
            }
        }
        
        do {
            try process?.run()
        } catch {
            Task { @MainActor in
                outputText = "[Error] \(error.localizedDescription)\n"
                showOutput = true
                isProcessing = false
                
                // Send notification
                self.sendNotification(title: "Processing Error", body: "The PDF processing failed with error: \(error.localizedDescription)")
            }
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
    
    private func openMonoFile() {
        if let outputFile = outputFile {
            let monoPath = outputFile.path.replacingOccurrences(of: "-dual.pdf", with: "-mono.pdf")
            let monoURL = URL(fileURLWithPath: monoPath)
            NSWorkspace.shared.open(monoURL)
        }
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
    
    func sendNotification(title: String, body: String, url: URL? = nil) {
        // Check if we're running as a proper app bundle
        guard Bundle.main.bundleIdentifier != nil else {
            print("Warning: Not running as a proper app bundle. Notifications disabled.")
            return
        }
        
        let center = UNUserNotificationCenter.current()
        
        // Check authorization status before sending
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                print("Cannot send notification: Not authorized.")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = UNNotificationSound.default
            
            var userInfo: [AnyHashable: Any] = [:] // Use AnyHashable for keys
            if let url = url {
                userInfo["url"] = url.path // Store the path string
            }
            content.userInfo = userInfo
            
            // Deliver the notification immediately.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            
            // Add the request to the notification center.
            center.add(request) { error in
                if let error = error {
                    print("Error adding notification request: \(error.localizedDescription)")
                } else {
                    print("Notification scheduled: \(title) - \(body)")
                }
            }
        }
    }
    
    @MainActor
    func handleNotificationClick(urlPath: String?) {
        // Break down URL creation
        guard let path = urlPath else {
            print("Handling notification click: No URL path provided, opening app.")
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        // Create a proper file URL from the path
        let url = URL(fileURLWithPath: path)
        
        print("Handling notification click for URL: \(url.path)")
        if FileManager.default.fileExists(atPath: path) {
             NSWorkspace.shared.open(url)
        } else {
            print("File not found at path: \(path)")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    private func translate(_ text: String) async throws -> String {
        switch service {
        case .google:
            return try await GoogleTranslator.shared.translate(
                text: text,
                from: sourceLanguage.rawValue,
                to: targetLanguage.rawValue
            )
        case .deepl:
            return try await DeepLTranslator.shared.translate(
                text: text,
                from: sourceLanguage.rawValue,
                to: targetLanguage.rawValue
            )
        case .deeplx:
            return try await DeepLTranslator.shared.translate(
                text: text,
                from: sourceLanguage.rawValue,
                to: targetLanguage.rawValue
            )
        }
    }
}

@available(macOS 13.0, *)
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    private override init() {
        super.init()
        // Check if we're running as a proper app bundle
        if Bundle.main.bundleIdentifier == nil {
            print("Warning: Not running as a proper app bundle. NotificationDelegate may not function correctly.")
        }
    } // Make init private for singleton
    
    // Handle notification presentation in foreground
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Check if we're running as a proper app bundle
        if Bundle.main.bundleIdentifier == nil {
            print("Warning: Not running as a proper app bundle. Skipping notification presentation.")
            completionHandler([])
            return
        }
        
        print("Notification will present in foreground: \(notification.request.content.title)")
        // Show alert and play sound
        completionHandler([.banner, .sound]) // Use .banner for modern alert style
    }
    
    // Handle user interaction with the notification (e.g., clicking)
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Check if we're running as a proper app bundle
        if Bundle.main.bundleIdentifier == nil {
            print("Warning: Not running as a proper app bundle. Skipping notification handling.")
            completionHandler()
            return
        }
        
        let userInfo = response.notification.request.content.userInfo
        print("Notification activated: \(response.notification.request.content.title)")
        print("User Info: \(userInfo)")
        
        // Extract the URL path from userInfo
        let urlPath = userInfo["url"] as? String
        
        // Pass the path to the main actor for handling
        Task { @MainActor in // Ensure the whole block runs on MainActor
            // Find the processor instance
             if let window = NSApplication.shared.windows.first,
                let hostingController = window.contentViewController as? NSHostingController<ContentView> {
                 let processor = hostingController.rootView.processor
                 print("Found processor instance via window.")
                 processor.handleNotificationClick(urlPath: urlPath) // Calls @MainActor func
             } else {
                 print("Could not find PDFProcessor instance to handle notification click.")
                 // Break down URL creation for fallback
                 if let path = urlPath {
                     // Create a proper file URL from the path
                     let url = URL(fileURLWithPath: path)
                     print("Opening URL directly: \(url.path)")
                     if FileManager.default.fileExists(atPath: path) {
                         NSWorkspace.shared.open(url)
                     } else {
                          print("File not found at path: \(path), activating app.")
                          NSApplication.shared.activate(ignoringOtherApps: true)
                     }
                 } else {
                     print("Activating app directly (no path provided).")
                     NSApplication.shared.activate(ignoringOtherApps: true)
                 }
             }
        }

        completionHandler()
    }
}

// Translator protocols and implementations
protocol Translator: Sendable {
    func translate(text: String, from: String, to: String) async throws -> String
}

@available(macOS 13.0, *)
final class GoogleTranslator: Translator {
    static let shared = GoogleTranslator()
    private init() {}
    
    func translate(text: String, from: String, to: String) async throws -> String {
        // TODO: Implement Google Translate API
        return text
    }
}

@available(macOS 13.0, *)
final class DeepLTranslator: Translator {
    static let shared = DeepLTranslator()
    private init() {}
    
    func translate(text: String, from: String, to: String) async throws -> String {
        // TODO: Implement DeepL API
        return text
    }
} 
 