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
    
    func selectWhisperModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: ConfigKey.whisperModelPath)
        }
    }
    
    func selectLlamaModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: ConfigKey.llamaModelPath)
        }
    }
}

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    
    @AppStorage(ConfigKey.selectedMicrophoneID) private var selectedMicrophoneID: String = ""
    @AppStorage(ConfigKey.whisperModelPath) private var whisperModelPath: String = ""
    @AppStorage(ConfigKey.llamaModelPath) private var llamaModelPath: String = ""
    
    @AppStorage(ConfigKey.llmTemperature) private var llmTemperature: Double = 0.3
    @AppStorage(ConfigKey.llmMaxTokens) private var llmMaxTokens: Int = 200
    @AppStorage(ConfigKey.saveTranscripts) private var saveTranscripts: Bool = false
    @AppStorage(ConfigKey.modelProfile) private var modelProfile: ModelProfile = .fast
    
    var body: some View {
        TabView {
            // MARK: - General Settings
            Form {
                Section(header: Text("Audio").font(.headline)) {
                    Picker("Microphone:", selection: $selectedMicrophoneID) {
                        ForEach(viewModel.availableMicrophones, id: \.uniqueID) { mic in
                            Text(mic.localizedName).tag(mic.uniqueID)
                        }
                    }
                }
                
                Divider().padding(.vertical)
                
                Section(header: Text("Models").font(.headline)) {
                    HStack {
                        Text("Whisper:")
                        TextField("Select .bin model", text: $whisperModelPath)
                            .disabled(true)
                        Button("Browse...") {
                            viewModel.selectWhisperModel()
                        }
                    }
                    
                    HStack {
                        Text("LLM:")
                        TextField("Select .gguf model", text: $llamaModelPath)
                            .disabled(true)
                        Button("Browse...") {
                            viewModel.selectLlamaModel()
                        }
                    }
                }
            }
            .padding()
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            // MARK: - AI Settings
            Form {
                Section(header: Text("Generation").font(.headline)) {
                    HStack {
                        Text("Temperature:")
                        Slider(value: $llmTemperature, in: 0.0...1.0, step: 0.1)
                        Text(String(format: "%.1f", llmTemperature))
                            .frame(width: 40)
                    }
                    
                    HStack {
                        Text("Max Tokens:")
                        Slider(value: Binding(get: {
                            Double(llmMaxTokens)
                        }, set: {
                            llmMaxTokens = Int($0)
                        }), in: 50...1000, step: 10)
                        Text("\(llmMaxTokens)")
                            .frame(width: 40)
                    }
                    
                    Picker("Model Profile:", selection: $modelProfile) {
                        ForEach(ModelProfile.allCases, id: \.self) { profile in
                            Text(profile.rawValue.capitalized).tag(profile)
                        }
                    }
                }
            }
            .padding()
            .tabItem {
                Label("AI Tuning", systemImage: "brain.head.profile")
            }
            
            // MARK: - Privacy Settings
            Form {
                Section(header: Text("Data").font(.headline)) {
                    Toggle("Save Transcripts to Disk", isOn: $saveTranscripts)
                    Text("If enabled, conversation transcripts will be saved locally. By default, Butler processes everything in memory and discards it.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .tabItem {
                Label("Privacy", systemImage: "hand.raised")
            }
        }
        .frame(width: 550, height: 350)
    }
}
