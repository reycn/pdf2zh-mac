import SwiftUI
import UniformTypeIdentifiers

@available(macOS 13.0, *)
struct FileDropView: View {
    @Binding var showFilePicker: Bool
    @ObservedObject var processor: PDFProcessor
    @State private var isTargeted = false
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 32) {
            Text("")
                .padding()
                .frame(maxWidth: .infinity)
                .frame(height: 464)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((isTargeted || isHovered) ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke((isTargeted || isHovered) ? Color.accentColor : Color.gray, style: StrokeStyle(lineWidth: 2, dash: [5]))
                )
                .animation(.easeInOut(duration: 0.5), value: isTargeted)
                .animation(.easeInOut(duration: 0.5), value: isHovered)
                .overlay(
                    VStack {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 16)
                        
                        Text("Drop a PDF file here")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                )
                .onHover { hovering in
                    isHovered = hovering
                }
                .onTapGesture {
                    showFilePicker = true
                }
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
        .padding(24)
        .opacity(processor.selectedFile == nil ? 1 : 0)
        .animation(.easeInOut, value: processor.selectedFile)
    }
} 