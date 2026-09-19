import Foundation

enum PlatformGemmaInstallationIdentifierError: Error {
    case persistenceFailed
}

enum PlatformGemmaInstallationIdentifier {
    static func loadOrCreate(
        existing: String?,
        generate: () -> String = { UUID().uuidString },
        persist: (String) -> Bool
    ) throws -> String {
        if let existing = existing?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            return existing
        }

        let generated = generate()
        guard persist(generated) else {
            throw PlatformGemmaInstallationIdentifierError.persistenceFailed
        }
        return generated
    }
}
