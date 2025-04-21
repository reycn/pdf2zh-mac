import SwiftUI
import AppKit

struct FileItem: Identifiable {
    let id = UUID()
    var name: String
    var type: ItemType
    var children: [FileItem]?
    
    enum ItemType {
        case file
        case folder
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var recentFiles: [FileItem] = [] // Will be populated from processor later
    @State private var preferences: [FileItem] = []  // Will be populated from processor later
    @State private var version = "Version: 0.1.beta"
    
    
    var body: some View {
        List {
            Section {
                if appState.recentFiles.isEmpty {
                    Text("No recent outputs")
                        .foregroundColor(.secondary).padding(.leading, 22)
                            .padding(.top, 8)
                } else {
                    ForEach(appState.recentFiles.suffix(5)) { recent in
                        HStack(spacing: 8) {
                            // truncated name
                            let name = recent.name.count > 20 ? String(recent.name.prefix(20)) + "..." : recent.name
                            Text(name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Button(action: { NSWorkspace.shared.open(recent.dualURL) }) {
                                Image(systemName: "doc.text.image")
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Open the document in both languages")
                            Button(action: {
                                NSWorkspace.shared.open(recent.monoURL)
                                appState.succeededFilePath = recent.monoURL
                            }) {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Open the document translated")
                        }
                            .padding(.top, 8)
                            .padding(.leading, 22)
                    }
                }
            } header: {
                Label("Recents", systemImage: "clock")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 16) {
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $appState.autoOpenMono) {
                                    Text("Auto-open")
                                        .foregroundColor(.secondary)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                            }
                            .padding(.leading, 22)
                            .padding(.top, 8)

                            VStack(alignment: .leading, spacing: 8) {
                                Picker("Use      ", selection: $appState.selectedService) {
                                    ForEach(Service.allCases) { service in
                                        Text(service.rawValue).tag(service)
                                    }
                                }
                                .foregroundColor(.secondary)
                                .pickerStyle(.menu)
                            }.padding(.leading, 22)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("From    ", selection: $appState.selectedSourceLanguage) {
                                    ForEach(Language.allCases) { language in
                                        Text(language.rawValue).tag(language)
                                    }
                                }
                                .foregroundColor(.secondary)
                                .pickerStyle(.menu)
                            }.padding(.leading, 22)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("To         ", selection: $appState.selectedTargetLanguage) {
                                    ForEach(Language.allCases) { language in
                                        Text(language.rawValue).tag(language)
                                    }
                                }
                                .foregroundColor(.secondary)
                                .pickerStyle(.menu)
                            }.padding(.leading, 22)
                }
            } header: {
                Label("Preferences", systemImage: "gearshape")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 16) {

                            // Multi-threads slider
                            VStack(alignment: .leading, spacing: 8) {
                                let threadOptions = [1,  4, 8, 32]
                                Picker("Threads", selection: $appState.multiThreads) {
                                    ForEach(threadOptions, id: \.self) { t in
                                        Text("\(t)").tag(t)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .foregroundColor(.primary)
                                .help("Number of threads to use for translation")
                            }
                            .padding(.leading, 22)

                            // Prompt file picker
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Custom prompt")
                                    Spacer()
                                    Button(action: {
                                        Task { // No 'await' needed here
                                            appState.pickPromptFile { path in
                                                if let path = path {
                                                    appState.promptPath = path
                                                }
                                            }
                                        }
                                    }) {
                                        Text("Select")
                                    }
                                    .foregroundColor(.primary)
                                    .help("Set a custom prompt file (--prompt)")
                                    if let prompt = appState.promptPath, !prompt.isEmpty {
                                        Text((prompt as NSString).lastPathComponent)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            }.padding(.leading, 22)
                            // Babeldoc toggle
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $appState.babeldoc) {
                                    Text("Use Babeldoc")
                                        .foregroundColor(.secondary)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .help("Enable --babeldoc option")
                            }
                            .padding(.leading, 22)

                            // Compatibility mode toggle
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $appState.compatibilityMode) {
                                    Text("Improve compatibility")
                                        .foregroundColor(.secondary)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .help("Enable compatibility mode (--skip-subset-fonts)")
                            }.padding(.leading, 22)


                            // Ignore cache toggle
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $appState.ignoreCache) {
                                    Text("Ignore cache")
                                        .foregroundColor(.secondary)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .help("Ignore translation cache (--ignore-cache)")
                            }.padding(.leading, 22)
                        }
                        .padding(.top, 8)
            } header: {
                Label("Advanced", systemImage: "wrench.and.screwdriver")
            }
        
        }
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(minWidth: 220)
        .onChange(of: appState.monoFilePath) { monoPath in
            if let mono = monoPath, appState.autoOpenMono {
                NSWorkspace.shared.open(mono)
                appState.succeededFilePath = mono
            }
        }
        .safeAreaInset(edge: .bottom) {
        VStack {
            if appState.succeededFilePath != nil {
                // Success section with output buttons
                HStack(spacing: 8) {
                    Text("Success!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack {
                        if let dual = appState.dualFilePath {
                            Button(action: { NSWorkspace.shared.open(dual) }) {
                                Image(systemName: "doc.text.image")
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Open the document in both languages")
                        }
                        if let mono = appState.monoFilePath {
                            Button(action: {
                                NSWorkspace.shared.open(mono)
                                appState.succeededFilePath = mono
                            }) {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Open the document transalted")
                        }
                    }
                }
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: {
                    appState.currentProcess = nil
                    appState.filePath = nil
                    appState.succeededFilePath = nil
                    appState.dualFilePath = nil
                    appState.monoFilePath = nil
                    appState.processOutput = ""
                    appState.showGuidance = false
                    appState.progress = nil
                }) {
                    Text("Start over")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Reset and start over")
                .padding(.bottom, 8)
            } else if appState.currentProcess != nil {
                // Processing section
                VStack {
                    HStack {
                        Text("Processing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            appState.currentProcess?.terminate()
                            appState.currentProcess = nil
                            appState.filePath = nil
                            appState.succeededFilePath = nil
                            appState.dualFilePath = nil
                            appState.monoFilePath = nil
                            appState.processOutput = ""
                            appState.showGuidance = false
                            appState.progress = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    ProgressView(value: appState.progress ?? 0)
                        .progressViewStyle(.linear)
                        .foregroundColor(.primary)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: appState.progress) { newProgress in
                            DispatchQueue.main.async {
                                appState.progress = newProgress
                            }
                        }
                }
            }
            HStack {
                Text(version)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Link("GitHub", destination: URL(string: "https://github.com/reycn/pdf2zh-mac")!)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    }
    
}