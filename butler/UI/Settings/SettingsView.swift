import SwiftUI
import AVFoundation

class SettingsViewModel: ObservableObject {
    @Published var selectedMicrophoneID: String = ""
    @Published var whisperModelPath: String = ""
    @Published var llamaModelPath: String = ""
    
    @Published var availableMicrophones: [AVCaptureDevice] = []
    
    init() {
        fetchMicrophones()
        // Load settings from UserDefaults in future
    }
    
    func fetchMicrophones() {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone, .externalUnknown], mediaType: .audio, position: .unspecified)
        availableMicrophones = discoverySession.devices
        if selectedMicrophoneID.isEmpty, let first = availableMicrophones.first {
            selectedMicrophoneID = first.uniqueID
        }
    }
    
    func selectWhisperModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            whisperModelPath = url.path
            // Save to UserDefaults
        }
    }
    
    func selectLlamaModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            llamaModelPath = url.path
            // Save to UserDefaults
        }
    }
}

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    
    var body: some View {
        Form {
            Section(header: Text("Audio").font(.headline)) {
                Picker("Microphone", selection: $viewModel.selectedMicrophoneID) {
                    ForEach(viewModel.availableMicrophones, id: \.uniqueID) { mic in
                        Text(mic.localizedName).tag(mic.uniqueID)
                    }
                }
            }
            
            Divider().padding(.vertical)
            
            Section(header: Text("Models").font(.headline)) {
                HStack {
                    Text("Whisper Model:")
                    TextField("Select .bin model", text: $viewModel.whisperModelPath)
                        .disabled(true)
                    Button("Browse...") {
                        viewModel.selectWhisperModel()
                    }
                }
                
                HStack {
                    Text("Llama Model:")
                    TextField("Select .gguf model", text: $viewModel.llamaModelPath)
                        .disabled(true)
                    Button("Browse...") {
                        viewModel.selectLlamaModel()
                    }
                }
            }
        }
        .padding()
        .frame(width: 500, height: 300)
    }
}
