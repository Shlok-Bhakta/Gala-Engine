import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class GalaNotifications {
    static let shared = GalaNotifications()
    private(set) var status = "Off"
    private(set) var enabled = false
    private(set) var responseSequence = 0
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var registeredServer: URL?
    @ObservationIgnored private var uploading = false
    @ObservationIgnored private var registering = false
    @ObservationIgnored private var registrationStarted = Date.distantPast
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        return URLSession(configuration: configuration)
    }()

    func enable(server: URL?) async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { status = "Allow notifications in Settings"; return }
            await sync(server: server)
        } catch {
            status = "Couldn't enable notifications"
        }
    }

    func sync(server: URL?) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        enabled = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        guard enabled else {
            status = settings.authorizationStatus == .denied ? "Allow notifications in Settings" : "Off"
            return
        }
        guard let server else { registeredServer = nil; status = "Add your Mac first"; return }
        guard let environment = environment else { status = "This build needs push-enabled signing"; return }
        guard let token else {
            // APNs may never answer while offline, so let a later sync ask again.
            if !registering || Date().timeIntervalSince(registrationStarted) > 20 {
                registering = true
                registrationStarted = Date()
                status = "Connecting to Apple…"
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }
        guard registeredServer != server, !uploading else { return }
        uploading = true
        defer { uploading = false }
        status = "Connecting to your Mac…"
        let defaults = UserDefaults.standard
        let device = defaults.string(forKey: "gala.pushDevice") ?? UUID().uuidString
        defaults.set(device, forKey: "gala.pushDevice")
        do {
            var request = URLRequest(url: server.appending(path: "apns/subscribe"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["token": token, "environment": environment, "device": device])
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode == 503 { status = "Your Mac needs push setup"; return }
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
            registeredServer = server
            status = "On"
        } catch {
            status = "Can't reach your Mac. Check Tailscale."
        }
    }

    func registered(_ data: Data) {
        // Ask Apple on each launch. Keep the current token only in memory.
        token = data.map { String(format: "%02x", $0) }.joined()
        registering = false
        registeredServer = nil
        Task { await sync(server: GalaServer.url(UserDefaults.standard.string(forKey: "gala.serverURL") ?? "")) }
    }

    func registrationFailed() {
        registering = false
        status = "Couldn't connect to Apple. Try again."
    }

    func openedNotification() { responseSequence += 1 }

    private var environment: String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let profile = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any],
              let value = entitlements["aps-environment"] as? String,
              ["development", "production"].contains(value) else { return nil }
        return value
    }
}

@MainActor
final class GalaAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        GalaNotifications.shared.registered(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        GalaNotifications.shared.registrationFailed()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await GalaNotifications.shared.openedNotification()
    }
}
