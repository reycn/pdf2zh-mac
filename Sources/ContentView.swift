import SwiftUI
import PDFKit
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var isHovering: Bool = false

    var body: some View {
        ZStack {
            if let succeedURL = appState.succeededFilePath {
                PDFKitView(url: succeedURL)
            } else if let url = appState.filePath {
                PDFKitView(url: url)
            } else {
                VStack(spacing: 16) {
                    Image(nsImage: NSWorkspace.shared.icon(for: UTType.pdf))
                        .resizable()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.secondary)
                    Text("Drop or select a PDF file")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .onTapGesture {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType.pdf]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        appState.filePath = url
                    }
                }
                .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                    providers.first?.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, _) in
                        guard let item = item else { return }
                        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            DispatchQueue.main.async {
                                appState.filePath = url
                            }
                        } else if let url = item as? URL {
                            DispatchQueue.main.async {
                                appState.filePath = url
                            }
                        }
                    }
                    return true
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in isHovering = hovering }
        .foregroundColor(isHovering ? Color.primary.opacity(0.6) : Color.clear)
        .animation(.easeInOut(duration: 0.5), value: isHovering)
        .ignoresSafeArea(.all, edges: .top)
        .onChange(of: appState.filePath) { newURL in
            if let url = newURL {
                runTranslation(url: url)
            }
        }
        .alert("Tool Not Found", isPresented: $appState.showGuidance) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The pdf2zh tool was not found. Please install it in your PATH or activate a Conda environment containing pdf2zh.")
        }
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

    private func runTranslation(url: URL) {
        // show progress bar immediately
        appState.currentProcess = Process()
        appState.processOutput = ""
        appState.progress = 0
        // Capture preferences before background thread
        let serviceArg = appState.selectedService.cliArgument
        let srcCode = appState.selectedSourceLanguage.cliCode
        let tgtCode = appState.selectedTargetLanguage.cliCode
        let threads = appState.multiThreads
        let compat = appState.compatibilityMode
        let babeldoc = appState.babeldoc
        let promptPath = appState.promptPath
        let ignoreCache = appState.ignoreCache
        DispatchQueue.global(qos: .userInitiated).async {
            let whichTool = Process()
            whichTool.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            whichTool.arguments = ["pdf2zh"]
            let whichPipe = Pipe()
            whichTool.standardOutput = whichPipe
            do {
                try whichTool.run(); whichTool.waitUntilExit()
                let whichData = whichPipe.fileHandleForReading.readDataToEndOfFile()
                let whichPath = String(data: whichData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let toolPath: String
                if (!whichPath.isEmpty) {
                    toolPath = whichPath
                } else {
                    let zshWhich = Process()
                    zshWhich.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    zshWhich.arguments = ["-c", "source ~/.zshrc && which pdf2zh"]
                    let zshPipe = Pipe()
                    zshWhich.standardOutput = zshPipe
                    try zshWhich.run(); zshWhich.waitUntilExit()
                    let zshData = zshPipe.fileHandleForReading.readDataToEndOfFile()
                    let zshWhichPath = String(data: zshData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !zshWhichPath.isEmpty {
                        toolPath = zshWhichPath
                    } else {
                        DispatchQueue.main.async { appState.showGuidance = true }
                        return
                    }
                }
                // clear previous state and prepare process
                DispatchQueue.main.async {
                    appState.succeededFilePath = nil
                    appState.processOutput = ""
                    appState.progress = 0
                    appState.currentProcess = nil
                    appState.dualFilePath = nil
                    appState.monoFilePath = nil
                }
                let proc = Process()
                DispatchQueue.main.async {
                    appState.currentProcess = proc
                    appState.processOutput = ""
                    appState.progress = 0
                }
                proc.executableURL = URL(fileURLWithPath: toolPath)
                let outDir = url.deletingLastPathComponent()
                var args: [String] = [
                    url.path,
                    "-s", serviceArg,
                    "-li", srcCode,
                    "-lo", tgtCode,
                    "-o", outDir.path
                ]
                // Add threads
                args += ["-t", "\(threads)"]
                // Add compatibility mode
                if compat {
                    args.append("--skip-subset-fonts")
                }
                // Add babeldoc
                if babeldoc {
                    args.append("--babeldoc")
                }
                // Add prompt
                if let promptPath = promptPath, !promptPath.isEmpty {
                    args.append("--prompt")
                    args.append(promptPath)
                }
                // Add ignore cache
                if ignoreCache {
                    args.append("--ignore-cache")
                }
                proc.arguments = args
                let outPipe = Pipe(), errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                let outHandle = outPipe.fileHandleForReading
                outHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
                    let lastLine = chunk.components(separatedBy: .newlines).last ?? chunk
                    DispatchQueue.main.async {
                        if let (progressValue, label, timeRemaining) = parseProgress(from: lastLine) {
                            appState.progress = progressValue
                            appState.processOutput += "\n" + label + (timeRemaining.isEmpty ? "" : " " + timeRemaining)
                        } else {
                            appState.processOutput += "\n" + lastLine
                        }
                    }
                }
                let errHandle = errPipe.fileHandleForReading
                errHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
                    let lastLine = chunk.components(separatedBy: .newlines).last ?? chunk
                    // ignore argos-translate errors
                    guard !lastLine.lowercased().contains("argos-translate") else { return }
                    DispatchQueue.main.async {
                        if let (progressValue, label, timeRemaining) = parseProgress(from: lastLine) {
                            appState.progress = progressValue
                            appState.processOutput += "\n" + label + (timeRemaining.isEmpty ? "" : " " + timeRemaining)
                        } else {
                            appState.processOutput += "\nError: " + lastLine
                        }
                    }
                }
                proc.terminationHandler = { process in
                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil
                    DispatchQueue.main.async {
                        appState.currentProcess = nil
                        if process.terminationStatus == 0 {
                            let root = url.deletingPathExtension().path
                            let dualURL = URL(fileURLWithPath: root + "-dual.pdf")
                            let monoURL = URL(fileURLWithPath: root + "-mono.pdf")
                            appState.dualFilePath = dualURL
                            appState.monoFilePath = monoURL
                            // preview mono by default
                            appState.succeededFilePath = monoURL
                            // add to recent files
                            let recent = RecentFile(name: url.lastPathComponent, dualURL: dualURL, monoURL: monoURL)
                            appState.recentFiles.insert(recent, at: 0)
                        }
                    }
                }
                DispatchQueue.main.async { appState.currentProcess = proc; appState.processOutput = ""; appState.progress = 0 }
                try proc.run()
            } catch {
                DispatchQueue.main.async {
                    appState.processOutput = "Failed to run translation: \(error.localizedDescription)"
                    print(appState.processOutput)
                    appState.currentProcess = nil
                }
            }
        }
    }
}

// PDFKitView for displaying the first page of a PDF
struct PDFKitView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        // Add observer to handle container size changes
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: pdfView.enclosingScrollView,
            queue: nil) { _ in
                // Dispatch to main thread since adjustZoomToFitWidth is main actor-isolated
                DispatchQueue.main.async {
                    adjustZoomToFitWidth(pdfView)
                }
        }
        
        // Hide scrollbars
        if let scrollView = pdfView.enclosingScrollView {
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.scrollerStyle = .overlay
        }
        
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        guard nsView.document?.documentURL != url else { return }
        nsView.document = PDFDocument(url: url)
        adjustZoomToFitWidth(nsView)
    }
    
    private func adjustZoomToFitWidth(_ pdfView: PDFView) {
        guard let pdfPage = pdfView.document?.page(at: 0),
              let scrollView = pdfView.enclosingScrollView else { return }
        
        let contentWidth = scrollView.contentView.bounds.width
        let pdfPageBounds = pdfPage.bounds(for: pdfView.displayBox)
        
        // Calculate scale factor needed to fit PDF width to view width
        // Account for some margin to avoid cutting off edges
        let margin: CGFloat = 30.0
        let scaleFactor = (contentWidth - margin) / pdfPageBounds.width
        
        // Only adjust if we have a reasonable scale factor
        if scaleFactor > 0 {
            pdfView.scaleFactor = scaleFactor
        }
    }
}