import Foundation
import Observation
import UIKit

struct GalaBuild: Decodable, Identifiable, Equatable {
    let project: String
    let title: String
    let version: String
    let sha256: String
    let bytes: Int
    let publishedAt: TimeInterval
    let bundleId: String
    let icon: String?

    var id: String { project }
    var publishedDate: Date { Date(timeIntervalSince1970: publishedAt) }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}

enum InstallPhase: Equatable {
    case starting
    case downloading(Double)
    case finishing
    case failed(String)

    var isBusy: Bool {
        if case .failed = self { return false }
        return true
    }
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

@MainActor
@Observable
final class GalaModel {
    private(set) var builds: [GalaBuild] = []
    private(set) var phases: [String: InstallPhase] = [:]
    private(set) var icons: [String: UIImage] = [:]
    private(set) var hasLoaded = false
    private(set) var isOffline = false
    private(set) var installed = UserDefaults.standard.dictionary(forKey: "gala.installed") as? [String: String] ?? [:]

    @ObservationIgnored private var loadedServer: URL?
    @ObservationIgnored private var attempts: [String: String] = [:]
    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var activeSince = Date.now
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        return URLSession(configuration: configuration)
    }()
    @ObservationIgnored private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func refresh(server: URL?) async {
        if server != loadedServer {
            loadedServer = server
            builds = []
            hasLoaded = false
            isOffline = false
        }
        guard let server else { return }
        do {
            let (data, response) = try await session.data(from: server.appending(path: "projects.json"))
            try check(response)
            let fresh = try decoder.decode([GalaBuild].self, from: data)
            guard server == loadedServer else { return }
            if fresh != builds { builds = fresh }
            isOffline = false
            hasLoaded = true
            await loadIcons(for: fresh, server: server)
        } catch {
            guard !Task.isCancelled, server == loadedServer else { return }
            isOffline = true
            hasLoaded = true
        }
    }

    func sceneChanged(active: Bool) {
        isActive = active
        if active { activeSince = .now }
    }

    func install(_ build: GalaBuild, server: URL) async {
        let project = build.project
        phases[project] = .starting
        do {
            var request = URLRequest(url: server.appending(path: project).appending(path: "attempt"))
            request.httpMethod = "POST"
            let (data, response) = try await session.data(for: request)
            try check(response)
            let attempt = try decoder.decode(InstallAttempt.self, from: data)
            guard let installURL = URL(string: attempt.installUrl),
                  let statusURL = URL(string: attempt.statusUrl) else {
                throw URLError(.badURL)
            }
            attempts[project] = attempt.attempt
            if !(await UIApplication.shared.open(installURL)), let webURL = URL(string: attempt.webUrl) {
                await UIApplication.shared.open(webURL)
            }
            await follow(project: project, sha256: build.sha256, token: attempt.attempt, statusURL: statusURL)
        } catch {
            phases[project] = .failed("Couldn’t start the install")
        }
    }

    private func follow(project: String, sha256: String, token: String, statusURL: URL) async {
        let started = Date.now
        var misses = 0
        while attempts[project] == token {
            try? await Task.sleep(for: .milliseconds(500))
            guard attempts[project] == token else { return }
            let status: TransferStatus
            do {
                let (data, response) = try await session.data(from: statusURL)
                try check(response)
                status = try decoder.decode(TransferStatus.self, from: data)
                misses = 0
            } catch {
                misses += 1
                if misses >= 6 { end(project, token, .failed("Lost connection to your Mac")) }
                continue
            }
            switch status.stage {
            case "ready", "manifest":
                // iOS asks before downloading. Back in the app with no download means
                // the prompt was cancelled; keep watching quietly in case it was slow.
                if phases[project] == .starting, isActive, Date.now.timeIntervalSince(max(started, activeSince)) > 5 {
                    phases[project] = nil
                }
                if Date.now.timeIntervalSince(started) > 60 { end(project, token, nil) }
            case "downloading":
                phases[project] = .downloading(min(1, Double(status.sent) / Double(max(1, status.total))))
            case "transferred":
                installed[project] = sha256
                UserDefaults.standard.set(installed, forKey: "gala.installed")
                phases[project] = .finishing
                try? await Task.sleep(for: .seconds(4))
                if attempts[project] == token { end(project, token, nil) }
            case "interrupted":
                end(project, token, .failed("Download interrupted"))
            case "superseded":
                end(project, token, nil)
                await refresh(server: loadedServer)
            default:
                break
            }
        }
    }

    private func end(_ project: String, _ token: String, _ phase: InstallPhase?) {
        guard attempts[project] == token else { return }
        attempts[project] = nil
        phases[project] = phase
    }

    private func loadIcons(for builds: [GalaBuild], server: URL) async {
        let missing = builds.compactMap(\.icon).filter { icons[$0] == nil }
        guard !missing.isEmpty else { return }
        let session = session
        var root = server.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for path in missing {
                guard let url = URL(string: root + "/" + path) else { continue }
                group.addTask {
                    let data = try? await session.data(from: url).0
                    return (path, data.flatMap(UIImage.init(data:)))
                }
            }
            for await (path, image) in group {
                if let image { icons[path] = image }
            }
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
