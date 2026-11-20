import Darwin
import Foundation

// CommerceKitSigner comes from the app target's bridging header.
enum AppleActionSigner {
    private static let queue = DispatchQueue(label: "dev.zach.mitori.commercekit-signer")

    static func sign(_ data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try signSynchronously(data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func signSynchronously(_ data: Data) throws -> String {
        var output: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = data.withUnsafeBytes { bytes in
            MitoriCommerceKitSign(
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count,
                &output,
                &outputLength,
                &errorMessage
            )
        }
        defer { free(errorMessage) }

        guard status == 0 else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown CommerceKit error"
            throw AppleActionSignerError.failed(message)
        }
        guard let output, outputLength > 0 else {
            throw AppleActionSignerError.failed("CommerceKit returned an empty signature")
        }
        defer { free(output) }

        return Data(bytes: output, count: outputLength).base64EncodedString()
    }
}

private enum AppleActionSignerError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            return "Apple action signing failed: \(message)"
        }
    }
}
