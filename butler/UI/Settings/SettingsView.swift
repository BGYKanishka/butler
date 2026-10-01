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
                        .contentShape(Circle())
                }
                .buttonStyle(IconButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)
            .padding(.bottom, 16)
            
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
                    HStack {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(.blue)
                        Text("PROJECT CONTEXT")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        if projectContextManager.isAnalyzing {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                            Text("Analyzing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if projectContextManager.needsReanalysis {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Reanalysis recommended")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else if let context = projectContextManager.currentContext {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("\(context.projectNames.count) projects • \(context.summary.count) chars")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(spacing: 0) {
                        if projectContextManager.projectURLs.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("No Projects Selected")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(.white)
                                Text("Add the codebase folders you want Butler to understand.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                Button(action: {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.allowsMultipleSelection = true
                                    
                                    if panel.runModal() == .OK, !panel.urls.isEmpty {
                                        for url in panel.urls {
                                            projectContextManager.addProject(url)
                                        }
                                    }
                                }) {
                                    Text("Add Folders")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .background(Color.blue)
                                .cornerRadius(6)
                                .padding(.top, 4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .padding(.horizontal, 16)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    .foregroundColor(.secondary.opacity(0.2))
                            )
                        } else {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(Array(projectContextManager.projectURLs.enumerated()), id: \.element) { index, url in
                                        HStack(spacing: 12) {
                                            Image(systemName: "folder.fill")
                                                .foregroundColor(.blue.opacity(0.8))
                                                .font(.system(size: 20))
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(url.lastPathComponent)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(.white)
                                                Text(url.path)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                projectContextManager.removeProject(at: IndexSet(integer: index))
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red.opacity(0.8))
                                                    .padding(6)
                                                    .contentShape(Rectangle())
                                            }
                                            .buttonStyle(PlainHoverButtonStyle())
                                            .disabled(projectContextManager.isAnalyzing)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        
                                        if index < projectContextManager.projectURLs.count - 1 {
                                            Divider()
                                                .background(Color.white.opacity(0.1))
                                                .padding(.leading, 40)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 180)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            
                            HStack {
                                Spacer()
                                
                                Button(action: {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.allowsMultipleSelection = true
                                    if panel.runModal() == .OK, !panel.urls.isEmpty {
                                        for url in panel.urls {
                                            projectContextManager.addProject(url)
                                        }
                                    }
                                }) {
                                    Label("Add Folders", systemImage: "plus")
                                        .font(.caption)
                                }
                                .disabled(projectContextManager.isAnalyzing)
                                .padding(.trailing, 8)
                                
                                Button(action: {
                                    projectContextManager.analyzeProjects()
                                }) {
                                    Label("Analyze Now", systemImage: "sparkles")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(projectContextManager.isAnalyzing ? Color.gray.opacity(0.3) : Color.blue)
                                        .cornerRadius(6)
                                }
                                .disabled(projectContextManager.isAnalyzing || projectContextManager.projectURLs.isEmpty)
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.top, 12)
                        }
                    }
                }
                
                // Permissions
                VStack(alignment: .leading, spacing: 12) {
                    Text("PERMISSIONS").font(.caption).foregroundColor(.secondary)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Microphone")
                                .foregroundColor(.white)
                            Text(permissionsGateway.isMicGranted ? "Access granted" : "Required for voice input")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if permissionsGateway.isMicGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Button("Request Access") {
                                Task { await permissionsGateway.requestMicPermission() }
                            }
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screen & System Audio")
                                .foregroundColor(.white)
                            Text(permissionsGateway.isScreenGranted ? "Access granted" : "Required for system audio capture")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if permissionsGateway.isScreenGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else if permissionsGateway.screenPermission.isRequestInProgress {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Waiting…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Button("Cancel") {
                                    permissionsGateway.screenPermission.cancelRequest()
                                }
                                .font(.caption)
                            }
                        } else {
                            Button("Request Access") {
                                permissionsGateway.requestScreenPermission()
                            }
                        }
                    }
                }
                
                // Updates
                VStack(alignment: .leading, spacing: 12) {
                    Text("UPDATES").font(.caption).foregroundColor(.secondary)
                    
                    HStack {
                        Text("Application Updates")
                            .foregroundColor(.white)
                        Spacer()
                        Button("Check for Updates") {
                            NSApp.sendAction(#selector(AppDelegate.checkForUpdates), to: nil, from: nil)
                        }
                    }
                }
                
                Spacer()
                

            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 350, height: 550)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
