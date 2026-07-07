import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device Apple Intelligence text generation via the Foundation Models framework.
/// Private Cloud Compute is not exposed to third-party apps, so both "models" run on-device
/// (the system itself decides when to use PCC). Image input isn't supported on-device — vision
/// tasks fall back to a clear error so the user picks a cloud provider.
enum AppleIntelligence {
    static func complete(prompt: String, hasImage: Bool) async throws -> String {
        if hasImage { throw AIError.appleNoVision }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                return response.content
            case .unavailable:
                throw AIError.appleUnavailable
            @unknown default:
                throw AIError.appleUnavailable
            }
        } else {
            throw AIError.appleUnavailable
        }
        #else
        throw AIError.appleUnavailable
        #endif
    }
}
