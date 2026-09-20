import Foundation

class ModelManager {
    func validateModel(at path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
    func downloadModels() async throws {
        let scriptPath = Bundle.main.path(forResource: "download_models", ofType: "sh") ?? ""
        guard FileManager.default.fileExists(atPath: scriptPath) else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        
        try process.run()
        process.waitUntilExit()
    }
}
