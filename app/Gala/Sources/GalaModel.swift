import Combine
import Foundation
import UIKit

struct GalaBuild: Decodable, Identifiable {
    let project: String
    let title: String
    let version: String
    let sha256: String
    let bytes: Int
    let publishedAt: TimeInterval
    let bundleId: String

    var id: String { project }
    var publishedDate: Date { Date(timeIntervalSince1970: publishedAt) }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}

private struct InstallAttempt: Decodable {
    let attempt: String
    let installUrl: String
    let statusUrl: String
    let webUrl: String
}

private struct TransferStatus: Decodable {
    let stage: String
    let sent: Int
    let total: Int
}

struct InstallProgress {
    let stage: String
    let sent: Int
    let total: Int
    let message: String?

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(sent) / Double(total))
    }

    var heading: String {
        switch stage {
        case "ready": "Waiting for iOS"
        case "manifest": "iOS found the build"
        case "downloading": "Sending IPA to iOS"
        case "transferred": "Transfer complete"
        case "interrupted": "Transfer interrupted"
        case "superseded": "A newer build is ready"
        default: "Opening the installer"
        }
    }

    var detail: String {
        if let message { return message }
        return switch stage {
        case "ready": "Keep Tailscale connected. The installer should request the build in a moment."
        case "manifest": "The manifest arrived. Waiting for the IPA request."
        case "downloading": "\(Int(fraction * 100))% of the IPA has been sent by Gala."
        case "transferred": "iOS finishes the installation. Close and reopen an app that was already running."
        case "interrupted": "Check Tailscale and tap Install again."
        case "superseded": "Refresh the build list before installing."
        default: "If iOS switches away, return here to see the transfer."
        }
    }
}

@MainActor
final class GalaModel: ObservableObject {
    @Published private(set) var builds: [GalaBuild] = []
    @Published private(set) var progress: [String: InstallProgress] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published var error: String?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func refresh(server: URL?) async {
        guard let server else {
            builds = []
            error = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: server.appendingPathComponent("projects.json"))
            try check(response)
            builds = try decoder.decode([GalaBuild].self, from: data)
            lastUpdated = .now
            error = nil
        } catch {
            self.error = "Cannot reach the Mac. Check Tailscale and the server address."
        }
    }

    func install(_ build: GalaBuild, server: URL) async {
        progress[build.project] = InstallProgress(stage: "opening", sent: 0, total: build.bytes, message: nil)
        do {
            var request = URLRequest(url: server.appendingPathComponent(build.project).appendingPathComponent("attempt"))
            request.httpMethod = "POST"
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(response)
            let attempt = try decoder.decode(InstallAttempt.self, from: data)
            guard let installURL = URL(string: attempt.installUrl),
                  let statusURL = URL(string: attempt.statusUrl) else {
                throw URLError(.badURL)
            }
            UIApplication.shared.open(installURL, options: [:]) { accepted in
                if !accepted, let webURL = URL(string: attempt.webUrl) {
                    Task { @MainActor in
                        UIApplication.shared.open(webURL)
                    }
                }
            }
            Task { await watch(project: build.project, statusURL: statusURL) }
        } catch {
            progress[build.project] = InstallProgress(
                stage: "interrupted", sent: 0, total: build.bytes,
                message: "Could not start the install. Check Tailscale and try again."
            )
        }
    }

    private func watch(project: String, statusURL: URL) async {
        for _ in 0..<180 {
            do {
                let (data, response) = try await URLSession.shared.data(from: statusURL)
                try check(response)
                let status = try decoder.decode(TransferStatus.self, from: data)
                progress[project] = InstallProgress(
                    stage: status.stage, sent: status.sent, total: status.total, message: nil
                )
                if ["transferred", "interrupted", "superseded"].contains(status.stage) { return }
            } catch {
                progress[project] = InstallProgress(
                    stage: "interrupted", sent: 0, total: 0,
                    message: "The Mac stopped reporting transfer progress. Check Tailscale."
                )
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func check(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

enum GalaServer {
    static let bundled = Bundle.main.object(forInfoDictionaryKey: "GalaDefaultServer") as? String ?? ""

    static func url(_ saved: String) -> URL? {
        let value = (saved.isEmpty ? bundled : saved).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
