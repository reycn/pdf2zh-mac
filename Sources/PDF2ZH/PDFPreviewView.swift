import SwiftUI
import PDFKit

@available(macOS 13.0, *)
struct PDFPreviewView: View {
    let url: URL?
    let title: String
    
    var body: some View {
        let _ = print("[PDFPreviewView] Body evaluated. URL: \(url?.path ?? "nil")")
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let url = url {
                let _ = print("[PDFPreviewView] Creating PDFKitView for URL: \(url.path)")
                PDFKitView(url: url)
                    .frame(height: 500)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            } else {
                let _ = print("[PDFPreviewView] URL is nil, showing placeholder.")
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 500)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(8)
                    .overlay(
                        Text("No PDF selected")
                            .foregroundColor(.secondary)
                    )
            }
        }
        .padding(.horizontal, 24)
    }
}

@available(macOS 13.0, *)
struct PDFKitView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> PDFView {
        let _ = print("[PDFKitView] makeNSView called for URL: \(url.path)")
        let pdfView = PDFView()
        
        // Basic configuration
        pdfView.autoScales = false
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        
        // Hide scroll bars
        if let scrollView = pdfView.enclosingScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
        }
        
        // Configure PDF view for better width fitting
        pdfView.maxScaleFactor = 2.0
        pdfView.minScaleFactor = 0.25
        pdfView.displaysAsBook = false
        pdfView.displaysPageBreaks = false
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            pdfView.goToFirstPage(nil)
            
            // Calculate scale to fit width
            if let page = document.page(at: 0) {
                let pageRect = page.bounds(for: .mediaBox)
                let viewWidth = pdfView.bounds.width
                let scale = viewWidth / pageRect.width
                pdfView.scaleFactor = scale
            }
        }
        
        // Add observer for window resize
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if let document = pdfView.document,
                    let page = document.page(at: 0) {
                    let pageRect = page.bounds(for: .mediaBox)
                    let viewWidth = pdfView.bounds.width
                    let scale = viewWidth / pageRect.width
                    pdfView.scaleFactor = scale
                }
            }
        }
        
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        let _ = print("[PDFKitView] updateNSView called for URL: \(url.path)")
        if let document = PDFDocument(url: url) {
            nsView.document = document
            nsView.goToFirstPage(nil)
            
            // Recalculate scale to fit width
            if let page = document.page(at: 0) {
                let pageRect = page.bounds(for: .mediaBox)
                let viewWidth = nsView.bounds.width
                let scale = viewWidth / pageRect.width
                nsView.scaleFactor = scale
            }
        }
    }
    
    static func dismantleNSView(_ nsView: PDFView, coordinator: ()) {
        // Remove observer when view is dismantled
        NotificationCenter.default.removeObserver(nsView)
    }
} 