import SwiftUI

@main
struct GalaApp: App {
    @StateObject private var model = GalaModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                BuildLibraryView()
                    .tabItem { Label("Builds", systemImage: "square.stack.3d.up.fill") }
                GalaSettingsView()
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            }
            .tint(GalaPalette.forest)
            .preferredColorScheme(.light)
            .environmentObject(model)
        }
    }
}

enum GalaPalette {
    static let forest = Color(red: 0.12, green: 0.31, blue: 0.22)
    static let leaf = Color(red: 0.72, green: 0.86, blue: 0.56)
    static let coral = Color(red: 0.92, green: 0.44, blue: 0.33)
    static let cream = Color(red: 0.97, green: 0.97, blue: 0.93)
    static let ink = Color(red: 0.15, green: 0.25, blue: 0.18)
}

private struct OrchardBackground: View {
    var body: some View {
        ZStack {
            GalaPalette.cream
            Circle()
                .fill(GalaPalette.leaf.opacity(0.35))
                .frame(width: 390, height: 390)
                .blur(radius: 75)
                .offset(x: 170, y: -290)
            Circle()
                .fill(GalaPalette.coral.opacity(0.15))
                .frame(width: 360, height: 360)
                .blur(radius: 85)
                .offset(x: -180, y: 270)
        }
        .ignoresSafeArea()
    }
}

private struct BuildLibraryView: View {
    @EnvironmentObject private var model: GalaModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("gala.serverURL") private var savedServer = ""

    private var server: URL? { GalaServer.url(savedServer) }

    var body: some View {
        NavigationStack {
            ZStack {
                OrchardBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        if server == nil {
                            connectionCard
                        } else {
                            buildSection
                        }
                        Text("BUILT ON YOUR MAC  ·  PRIVATE ON YOUR TAILNET")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.1)
                            .foregroundStyle(GalaPalette.forest.opacity(0.56))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: 820)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await model.refresh(server: server) }
            }
            .navigationTitle("Gala")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh(server: server) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh builds")
                    .disabled(server == nil || model.isLoading)
                }
            }
            .task(id: savedServer) { await model.refresh(server: server) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.refresh(server: server) }
                }
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(
                    colors: [GalaPalette.forest, Color(red: 0.17, green: 0.42, blue: 0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Circle()
                .stroke(.white.opacity(0.11), lineWidth: 34)
                .frame(width: 210, height: 210)
                .offset(x: 255, y: -55)
            VStack(alignment: .leading, spacing: 12) {
                Label("YOUR PRIVATE BUILD STATION", systemImage: "leaf.fill")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.3)
                    .foregroundStyle(GalaPalette.leaf)
                Text("Fresh builds.\nReady when you are.")
                    .font(.system(size: 35, weight: .bold, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("iPhone and iPad apps from your Mac, right here.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(26)
        }
        .frame(height: 235)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .accessibilityElement(children: .combine)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connect your Mac", systemImage: "network")
                .font(.title3.bold())
                .foregroundStyle(GalaPalette.ink)
            Text("Enter the private Gala URL in Settings. Tailscale must be connected on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                Text("Current builds")
                    .font(.title2.bold())
                    .foregroundStyle(GalaPalette.ink)
                Spacer()
                if model.isLoading {
                    ProgressView()
                        .accessibilityLabel("Loading builds")
                } else if model.error == nil {
                    Label("Mac online", systemImage: "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GalaPalette.forest)
                }
            }
            if let error = model.error {
                Label(error, systemImage: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(GalaPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
            } else if model.builds.isEmpty && !model.isLoading {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title)
                        .foregroundStyle(GalaPalette.coral)
                    Text("Nothing in the basket yet")
                        .font(.headline)
                    Text("Run gala deliver from a project. Its latest build will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 15)], spacing: 15) {
                ForEach(model.builds) { build in
                    buildCard(build)
                }
            }
        }
    }

    private func buildCard(_ build: GalaBuild) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 13) {
                Text(String(build.title.prefix(1)).uppercased())
                    .font(.title2.bold())
                    .foregroundStyle(GalaPalette.forest)
                    .frame(width: 52, height: 52)
                    .background(GalaPalette.leaf.opacity(0.48), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(build.title)
                        .font(.headline)
                        .foregroundStyle(GalaPalette.ink)
                    Text("Build \(build.version)  ·  \(build.formattedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Label {
                    Text(build.publishedDate, style: .relative)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "iphone.gen3")
                    .foregroundStyle(GalaPalette.forest.opacity(0.7))
                Image(systemName: "ipad")
                    .foregroundStyle(GalaPalette.forest.opacity(0.7))
            }
            if let state = model.progress[build.project] {
                VStack(alignment: .leading, spacing: 7) {
                    Text(state.heading)
                        .font(.subheadline.weight(.semibold))
                    if state.stage == "downloading" || state.stage == "transferred" {
                        ProgressView(value: state.fraction)
                            .tint(GalaPalette.coral)
                    } else if state.stage != "interrupted" {
                        ProgressView()
                            .tint(GalaPalette.coral)
                    }
                    Text(state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            HStack {
                Button {
                    guard let server else { return }
                    Task { await model.install(build, server: server) }
                } label: {
                    Label("Install update", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(GalaPalette.coral)
                if let server {
                    Link(destination: server.appendingPathComponent(build.project)) {
                        Image(systemName: "safari")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Open web installer")
                }
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

private struct GalaSettingsView: View {
    @AppStorage("gala.serverURL") private var savedServer = ""

    var body: some View {
        NavigationStack {
            ZStack {
                OrchardBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Mac connection", systemImage: "network")
                                .font(.title3.bold())
                            TextField("https://your-mac.tailnet.ts.net/gala", text: $savedServer)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .padding(13)
                                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
                            Text("This app starts with the Mac that built it. Enter a different Gala URL here to switch servers.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if savedServer.isEmpty && !GalaServer.bundled.isEmpty {
                                Text(GalaServer.bundled)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                                    .foregroundStyle(GalaPalette.forest)
                            }
                        }
                        .padding(22)
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Build alerts", systemImage: "bell.badge")
                                .font(.title3.bold())
                            Text("The current Home Screen app sends build notifications. Native push will need a Gala App ID with Apple's APNs entitlement.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let server = GalaServer.url(savedServer) {
                                Link(destination: server) {
                                    Label("Open build alerts", systemImage: "arrow.up.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glassProminent)
                                .tint(GalaPalette.forest)
                            }
                        }
                        .padding(22)
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))

                        VStack(alignment: .leading, spacing: 8) {
                            Label("About Gala", systemImage: "apple.terminal")
                                .font(.title3.bold())
                            Text("Native preview 0.1.0")
                                .font(.subheadline)
                            Text("Gala builds on your Mac and shows only the current IPA for each project. iOS handles the final install after the transfer.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(22)
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    }
                    .frame(maxWidth: 680)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
