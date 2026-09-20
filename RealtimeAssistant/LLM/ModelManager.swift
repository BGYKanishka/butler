import Foundation

class ModelManager {
    func validateModel(at path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
}
