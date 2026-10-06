import CoreText
import CryptoKit
import Foundation

// MARK: - Fetching

/// Why fetching one font file failed (PRD 0.3 FR-16.10).
enum FontFetchError: Error, Equatable {
    /// The device has no network connection; the fallback URL is not tried.
    case noNetwork
    /// Any other failure: a bad status, a dropped connection, a server error.
    case other
}

/// Downloads one file over the network. Injected so unit tests never connect.
///
/// Implementations write the body to `destination`, replacing anything there,
/// and honour task cancellation by throwing `CancellationError`.
protocol FontFileFetching: Sendable {
    /// Fetches `url` into `destination`. `progress` runs from 0 to 1 and may be
    /// called from any thread.
    func fetch(from url: URL,
               to destination: URL,
               progress: @escaping @Sendable (Double) -> Void) async throws
}

/// The `URLSession` implementation of `FontFileFetching`.
struct URLSessionFontFetcher: FontFileFetching {
    /// Seconds without progress before a request fails.
    static let requestTimeout: TimeInterval = 30

    func fetch(from url: URL,
               to destination: URL,
               progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        let delegate = ProgressDelegate(progress: progress)
        do {
            let (location, response) = try await URLSession.shared.download(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: location)
                throw FontFetchError.other
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch let error as FontFetchError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw Self.offlineCodes.contains(error.code) ? FontFetchError.noNetwork : FontFetchError.other
        } catch {
            throw FontFetchError.other
        }
    }

    /// `URLError` codes that mean "no connection" rather than a server problem.
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .networkConnectionLost
    ]

    /// Forwards download progress; the per-task delegate of the async API.
    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate {
        private let progress: @Sendable (Double) -> Void

        init(progress: @escaping @Sendable (Double) -> Void) {
            self.progress = progress
        }

        func urlSession(_ session: URLSession,
                        downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {}

        func urlSession(_ session: URLSession,
                        downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }
}

// MARK: - Verifying

/// Checks a downloaded font file against the catalog (PRD 0.3 §4.2).
enum FontFileVerifier {
    /// Whether the file at `url` has exactly the asset's size and SHA-256.
    ///
    /// Reads the whole file, so call it off the main actor.
    static func isValid(fileAt url: URL, for asset: OpenSourceFontAsset) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue == asset.byteCount,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return false
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == asset.sha256
    }
}

// MARK: - Registering

/// Registers a font file with CoreText for this process. Injected so unit tests
/// do not touch the real font manager.
protocol FontRegistering: Sendable {
    /// Registers the file; `true` if the font is now usable (including when it
    /// was already registered).
    func register(fontAt url: URL) -> Bool
    /// Removes the registration; a file that was never registered is ignored.
    func unregister(fontAt url: URL)
}

/// `CTFontManager` registration in the `.process` scope (PRD 0.3 §4.2).
struct CoreTextFontRegistrar: FontRegistering {
    func register(fontAt url: URL) -> Bool {
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        guard let error else { return false }
        let code = CFErrorGetCode(error.takeRetainedValue())
        return code == CTFontManagerError.alreadyRegistered.rawValue
    }

    func unregister(fontAt url: URL) {
        var error: Unmanaged<CFError>?
        _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &error)
        error?.release()
    }
}
