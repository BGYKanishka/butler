import SwiftUI
import AVFoundation

class SettingsViewModel: ObservableObject {
    @Published var availableMicrophones: [AVCaptureDevice] = []
    
    init() {
        fetchMicrophones()
    }
    
    func fetchMicrophones() {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        availableMicrophones = discoverySession.devices
        
        let selectedMic = UserDefaults.standard.string(forKey: ConfigKey.selectedMicrophoneID) ?? ""
        if selectedMic.isEmpty, let first = availableMicrophones.first {
            UserDefaults.standard.set(first.uniqueID, forKey: ConfigKey.selectedMicrophoneID)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var permissionsGateway: PermissionsGateway
    @ObservedObject var projectContextManager: ProjectContextManager
    @StateObject private var viewModel = SettingsViewModel()
    
    @AppStorage(ConfigKey.selectedMicrophoneID) private var selectedMicrophoneID: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    NSApp.sendAction(#selector(NSWindow.close), to: nil, from: nil)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
            }
            .padding(20)
            
            VStack(alignment: .leading, spacing: 24) {
                // Audio
                VStack(alignment: .leading, spacing: 12) {
                    Text("AUDIO").font(.caption).foregroundColor(.secondary)
                    Picker("Microphone", selection: $selectedMicrophoneID) {
                        ForEach(viewModel.availableMicrophones, id: \.uniqueID) { mic in
                            Text(mic.localizedName).tag(mic.uniqueID)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Project Context
                VStack(alignment: .leading, spacing: 12) {
                    Text("PROJECT CONTEXT").font(.caption).foregroundColor(.secondary)
                    
                    HStack {
                        if projectContextManager.isAnalyzing {
                            Text("Analyzing...").font(.caption).foregroundColor(.secondary)
                        } else if let vocabCount = projectContextManager.currentContext?.vocabulary.count {
                            Text("\(vocabCount) keywords extracted").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Analyze") {
                            projectContextManager.analyzeProjects()
                        }
                        .disabled(projectContextManager.isAnalyzing || projectContextManager.projectURLs.isEmpty)
                        
                        Button("Add Folders") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = true
                            
                            if panel.runModal() == .OK, !panel.urls.isEmpty {
                                for url in panel.urls {
                                    projectContextManager.addProject(url)
                                }
                            }
                        }
                        .disabled(projectContextManager.isAnalyzing)
                    }
                    
                    if projectContextManager.projectURLs.isEmpty {
                        Text("No Projects Selected")
                            .foregroundColor(.white)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                    } else {
                        List {
                            ForEach(Array(projectContextManager.projectURLs.enumerated()), id: \.element) { index, url in
                                HStack {
                                    Text(url.lastPathComponent)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: {
                                        projectContextManager.removeProject(at: IndexSet(integer: index))
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(projectContextManager.isAnalyzing)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .frame(height: 100)
                        .cornerRadius(8)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.05))
                    }
                }
                
                // Permissions
                VStack(alignment: .leading, spacing: 12) {
                    Text("PERMISSIONS").font(.caption).foregroundColor(.secondary)
                    
                    HStack {
                        Text("Microphone")
                            .foregroundColor(.white)
                        Spacer()
                        Button(permissionsGateway.isMicGranted ? "Granted" : "Request") {
                            Task { await permissionsGateway.requestMicPermission() }
                        }
                        .disabled(permissionsGateway.isMicGranted)
                    }
                    
                    HStack {
                        Text("Screen & System Audio")
                            .foregroundColor(.white)
                        Spacer()
                        Button(permissionsGateway.isScreenGranted ? "Granted" : "Request") {
                            permissionsGateway.requestScreenPermission()
                        }
                        .disabled(permissionsGateway.isScreenGranted)
                    }
                }
                
                Spacer()
                
                // Quit
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit Butler")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(Color.red.opacity(0.8))
                .cornerRadius(8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 350, height: 560) // Increased height for list
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
