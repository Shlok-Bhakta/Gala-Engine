import SwiftUI

@main
struct GalaApp: App {
    @UIApplicationDelegateAdaptor(GalaAppDelegate.self) private var appDelegate
    @State private var model = GalaModel()

    var body: some Scene {
        WindowGroup {
            BuildsView()
                .environment(model)
                .tint(.galaAccent)
                .preferredColorScheme(.dark)
        }
    }
}

extension Color {
    /// Gala's coral, tuned for text and strokes on dark surfaces.
    static let galaAccent = Color(red: 1, green: 0.482, blue: 0.361)
    /// A deeper coral for solid fills that carry white text.
    static let galaAccentFill = Color(red: 0.894, green: 0.345, blue: 0.227)
}

/// A faint coral and forest glow behind the navigation bar, so the glass has color to refract.
private struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [.galaAccent.opacity(0.2), .clear], center: UnitPoint(x: 0.9, y: -0.08),
                           startRadius: 0, endRadius: 360)
            RadialGradient(colors: [Color(red: 0.18, green: 0.49, blue: 0.32).opacity(0.26), .clear],
                           center: UnitPoint(x: 0.05, y: -0.1), startRadius: 0, endRadius: 340)
        }
        .ignoresSafeArea()
    }
}

private struct BuildsView: View {
    @Environment(GalaModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("gala.serverURL") private var savedServer = ""
    @State private var showSettings = false

    private var server: URL? { GalaServer.url(savedServer) }

    var body: some View {
        NavigationStack {
            content
                .background(AmbientBackground())
                .navigationTitle("Builds")
                .navigationSubtitle(model.isOffline && !model.builds.isEmpty ? "Offline" : "")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape") { showSettings = true }
                            .tint(.primary)
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
        }
        .task(id: "\(savedServer)|\(scenePhase == .active)") {
            model.sceneChanged(active: scenePhase == .active)
            guard scenePhase == .active else { return }
            // Poll while visible so a fresh delivery appears without a pull.
            while !Task.isCancelled {
                await GalaNotifications.shared.sync(server: server)
                await model.refresh(server: server)
                try? await Task.sleep(for: .seconds(8))
            }
        }
        .onChange(of: GalaNotifications.shared.responseSequence) {
            Task { await model.refresh(server: server) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if server == nil {
            ContentUnavailableView {
                Label("Connect to Your Mac", systemImage: "laptopcomputer")
            } description: {
                Text("Add your Gala server address to see your builds.")
            } actions: {
                Button("Add Server") { showSettings = true }
                    .buttonStyle(.glassProminent)
                    .tint(.galaAccentFill)
            }
        } else if model.builds.isEmpty {
            ScrollView {
                Group {
                    if !model.hasLoaded {
                        ProgressView()
                    } else if model.isOffline {
                        ContentUnavailableView {
                            Label("Can’t Reach Your Mac", systemImage: "wifi.slash")
                        } description: {
                            Text("Make sure Tailscale is connected on this device.")
                        } actions: {
                            Button("Try Again") { Task { await model.refresh(server: server) } }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("No Builds", systemImage: "square.stack.3d.up")
                        } description: {
                            Text("Run `gala deliver` in a project and it will show up here.")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length * 0.8 }
            }
            .refreshable { await model.refresh(server: server) }
        } else if let server {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 12)], spacing: 12) {
                    ForEach(model.builds) { build in
                        BuildRow(build: build, server: server)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .animation(.snappy, value: model.builds)
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .refreshable { await model.refresh(server: server) }
        }
    }
}

private struct BuildRow: View {
    let build: GalaBuild
    let server: URL
    @Environment(GalaModel.self) private var model
    @ScaledMetric(relativeTo: .title) private var iconSize = 60.0

    private var phase: InstallPhase? { model.phases[build.project] }
    private var webInstaller: URL { server.appending(path: build.project).appending(path: "") }

    var body: some View {
        HStack(spacing: 14) {
            AppIcon(build: build, image: build.icon.flatMap { model.icons[$0] }, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(build.title)
                    .font(.headline)
                    .lineLimit(1)
                detail
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            InstallControl(build: build, server: server, phase: phase)
        }
        .padding(.vertical, 14)
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 24))
        .contextMenu {
            Section("\(build.bundleId) · \(build.formattedSize)") {
                Link(destination: webInstaller) {
                    Label("Open in Safari", systemImage: "safari")
                }
                Button("Copy Link", systemImage: "link") {
                    UIPasteboard.general.url = webInstaller
                }
            }
        }
        .animation(.snappy, value: phase)
        .sensoryFeedback(.success, trigger: phase == .finishing) { _, finished in finished }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var detail: some View {
        switch phase {
        case .starting:
            Text("Starting…").foregroundStyle(.secondary)
        case .downloading:
            Text("Downloading…").foregroundStyle(.secondary)
        case .finishing:
            Text("Finishing on this device…").foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        case nil:
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text("Build \(build.version) · \(ago(build.publishedDate, now: context.date))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)h ago" : "\(hours / 24)d ago"
    }
}

private struct InstallControl: View {
    let build: GalaBuild
    let server: URL
    let phase: InstallPhase?
    @Environment(GalaModel.self) private var model

    var body: some View {
        Group {
            switch phase {
            case .starting:
                ProgressRing(fraction: nil)
                    .accessibilityLabel("Starting install")
            case .downloading(let fraction):
                ProgressRing(fraction: fraction)
                    .accessibilityLabel("Downloading")
                    .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
            case .finishing:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.galaAccent)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .accessibilityLabel("Downloaded")
            case .failed, nil:
                button
            }
        }
        .frame(minWidth: 80, minHeight: 44, alignment: .trailing)
    }

    private var button: some View {
        let installed = model.installed[build.project]
        let label = phase != nil ? "Retry" : installed == build.sha256 ? "Installed" : installed != nil ? "Update" : "Install"
        return Button {
            Task { await model.install(build, server: server) }
        } label: {
            Text(label)
                .font(.subheadline.weight(.bold))
                .frame(minWidth: 50)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(label == "Installed" ? .secondary : .galaAccent)
        .accessibilityLabel(label == "Installed" ? "Reinstall \(build.title)" : "\(label) \(build.title)")
    }
}

private struct ProgressRing: View {
    let fraction: Double?

    var body: some View {
        TimelineView(.animation(paused: fraction != nil)) { context in
            let spin = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction ?? 0.22)
                    .stroke(Color.galaAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(fraction == nil ? spin * 360 - 90 : -90))
                    .animation(.linear(duration: 0.3), value: fraction)
            }
        }
        .frame(width: 30, height: 30)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

private struct AppIcon: View {
    let build: GalaBuild
    let image: UIImage?
    let size: Double

    // The same palette and hash as the web dashboard, so each app keeps its color everywhere.
    private static let palettes: [(Color, Color)] = [
        (Color(red: 1, green: 0.604, blue: 0.478), Color(red: 0.894, green: 0.345, blue: 0.227)),
        (Color(red: 0.435, green: 0.812, blue: 0.557), Color(red: 0.180, green: 0.490, blue: 0.322)),
        (Color(red: 0.424, green: 0.706, blue: 1), Color(red: 0.184, green: 0.435, blue: 0.878)),
        (Color(red: 0.761, green: 0.608, blue: 1), Color(red: 0.478, green: 0.310, blue: 0.878)),
        (Color(red: 1, green: 0.816, blue: 0.420), Color(red: 0.910, green: 0.569, blue: 0.184)),
        (Color(red: 0.373, green: 0.847, blue: 0.800), Color(red: 0.118, green: 0.561, blue: 0.533)),
    ]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225)
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                let colors = Self.palettes[Int(hash % UInt32(Self.palettes.count))]
                LinearGradient(colors: [colors.0, colors.1], startPoint: .top, endPoint: .bottom)
                    .overlay {
                        Text(build.title.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5) }
        .accessibilityHidden(true)
    }

    private var hash: UInt32 {
        build.project.utf16.reduce(UInt32(7)) { $0 &* 31 &+ UInt32($1) }
    }
}

private struct SettingsView: View {
    @Environment(GalaModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gala.serverURL") private var savedServer = ""

    private var server: URL? { GalaServer.url(savedServer) }
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "–"
        let build = info["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server", text: $savedServer,
                              prompt: Text(GalaServer.bundled.isEmpty ? "https://mac.tailnet.ts.net/gala" : GalaServer.bundled))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .submitLabel(.done)
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            if server != nil && model.hasLoaded {
                                Circle()
                                    .fill(model.isOffline ? Color.red : Color.green)
                                    .frame(width: 8, height: 8)
                            }
                            Text(status)
                        }
                    }
                } header: {
                    Text("Mac")
                } footer: {
                    Text(GalaServer.bundled.isEmpty
                         ? "Your Gala address on your tailnet."
                         : "Leave empty to use the Mac this app was built on.")
                }

                Section {
                    LabeledContent("Build Alerts", value: GalaNotifications.shared.status)
                    if GalaNotifications.shared.status != "On" {
                        Button(GalaNotifications.shared.enabled ? "Retry Build Alerts" : "Enable Build Alerts") {
                            Task { await GalaNotifications.shared.enable(server: server) }
                        }
                        if let settings = URL(string: UIApplication.openSettingsURLString) {
                            Link("Notification Settings", destination: settings)
                        }
                    }
                } footer: {
                    Text("Get a notification when your Mac publishes a build. Tap it to open Gala, then choose Install.")
                }

                Section {
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var status: String {
        if server == nil { return savedServer.isEmpty ? "Not set" : "Invalid address" }
        if !model.hasLoaded { return "Checking…" }
        return model.isOffline ? "Not reachable" : "Connected"
    }
}
