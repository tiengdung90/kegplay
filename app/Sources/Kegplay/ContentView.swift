import SwiftUI

struct ContentView: View {
    @EnvironmentObject var backend: Backend
    @State private var selectedEngine = "dxmt"
    @State private var showLog = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let v = backend.updateVersion { updateBanner(v) }
            if backend.ready {
                controls
                Divider()
                gameList
            } else {
                firstRun
            }
            Divider()
            footer
        }
        .frame(minWidth: 880, minHeight: 540)   // 880: hàng nút bản tiếng Nga/Đức dài hơn tiếng Việt
        .overlay { if backend.busy { busyOverlay } }
        .onAppear { selectedEngine = backend.engine }
        .onChange(of: backend.engine) { new in if !backend.steamRunning { selectedEngine = new } }
        .alert("kegPlay", isPresented: Binding(get: { backend.alert != nil }, set: { if !$0 { backend.alert = nil } })) {
            Button(L("alert.viewLog")) { showLog = true; backend.alert = nil }
            Button(L("alert.help")) { backend.openHelp(); backend.alert = nil }
            Button(L("btn.close"), role: .cancel) { backend.alert = nil }
        } message: { Text(backend.alert ?? "") }
        .sheet(isPresented: $showLog) { LogSheet().environmentObject(backend) }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(backend) }
    }

    // MARK: - Các khối giao diện

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("kegPlay").font(.title2.bold())
                Text(L("app.tagline", backend.version))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func updateBanner(_ v: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
            Text(L("update.available", v)).font(.callout)
            Spacer()
            Button(L("update.get")) { backend.openReleases() }.controlSize(.small)
        }
        .padding(.horizontal, 18).padding(.vertical, 7)
        .background(Color.blue.opacity(0.10))
    }

    private var statusPill: some View {
        let (text, color): (String, Color) =
            !backend.ready ? (L("status.notInstalled"), .orange)
            : backend.steamRunning ? (L("status.running", backend.engine.uppercased()), .green)
            : (L("status.ready"), .blue)
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.callout)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var firstRun: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "shippingbox").font(.system(size: 46)).foregroundStyle(.secondary)
            Text(L("first.title")).font(.title2.bold())
            Text(L("first.body"))
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
            Button {
                Task { await backend.install() }
            } label: { Text(L("first.button")).frame(minWidth: 180) }
            .controlSize(.large).buttonStyle(.borderedProminent)
            Text(L("first.data", backend.dataRoot.path)).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
            Button(L("first.change")) { showSettings = true }.buttonStyle(.link).font(.caption)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("", selection: $selectedEngine) {
                Text(L("engine.dxmt")).tag("dxmt")
                Text("DXVK").tag("dxvk")
            }
            .pickerStyle(.segmented).frame(width: 250).labelsHidden()
            .disabled(backend.steamRunning)
            .help(backend.steamRunning ? L("engine.help.locked") : L("engine.help"))

            Button {
                Task { await backend.openSteam(engine: selectedEngine) }
            } label: { Label(L("btn.openSteam"), systemImage: "play.fill") }
            .buttonStyle(.borderedProminent).disabled(backend.steamRunning)

            Button(role: .destructive) {
                Task { await backend.stop() }
            } label: { Label(L("btn.stopSteam"), systemImage: "stop.fill") }
            .help(L("help.stop"))

            Spacer()

            Toggle(L("toggle.unblock"), isOn: Binding(
                get: { backend.unblock },
                set: { on in Task { await backend.setUnblock(on) } }))
            .toggleStyle(.switch)
            .help(L("help.unblock"))
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private var gameList: some View {
        Group {
            if backend.games.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "gamecontroller").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text(L("games.empty.title")).font(.title3.bold())
                    Text(L("games.empty.body"))
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 14)], spacing: 14) {
                        ForEach(backend.games) { game in
                            GameCard(game: game) { Task { await backend.play(game, engine: selectedEngine) } }
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(backend.log.last ?? L("footer.default"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(L("link.help")) { backend.openHelp() }.buttonStyle(.link).font(.caption)
                .help("kegplay.com/debug")
            Button(L("link.log")) { showLog = true }.buttonStyle(.link).font(.caption)
            Button(L("link.settings")) { showSettings = true }.buttonStyle(.link).font(.caption)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(backend.busyTitle).font(.headline)
                Text(backend.busyDetail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.center).frame(width: 380)
            }
            .padding(26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct GameCard: View {
    let game: Game
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: game.coverURL) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(460.0 / 215.0, contentMode: .fill)
                default:
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "gamecontroller.fill").font(.largeTitle).foregroundStyle(.secondary)
                    }
                    .aspectRatio(460.0 / 215.0, contentMode: .fit)
                }
            }
            .clipped()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name).font(.callout.bold()).lineLimit(1)
                    Text(game.ready ? game.sizeText : L("game.downloading")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: play) { Label(L("btn.play"), systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!game.ready)
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}

struct LogSheet: View {
    @EnvironmentObject var backend: Backend
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("link.log")).font(.headline)
                Spacer()
                Button(L("log.openFolder")) { backend.openLogs() }
                Button(L("btn.close")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(backend.log.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).id(i)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .onAppear { proxy.scrollTo(backend.log.count - 1, anchor: .bottom) }
                .onChange(of: backend.log.count) { n in proxy.scrollTo(n - 1, anchor: .bottom) }
            }
        }
        .padding(16).frame(width: 720, height: 460)
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var backend: Backend
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("link.settings")).font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("settings.data.title")).font(.callout.bold())
                Text(L("settings.data.desc"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(backend.dataRoot.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button(L("settings.reveal")) { backend.revealData() }
                    Button(L("settings.change")) { chooseFolder() }.disabled(backend.steamRunning)
                    Button(L("settings.default")) { backend.setDataRoot(Backend.defaultDataRoot) }
                        .disabled(backend.steamRunning || backend.dataRoot == Backend.defaultDataRoot)
                }
                Text(L("settings.reuse"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Picker(L("settings.language"), selection: Binding(get: { backend.language }, set: { backend.setLanguage($0) })) {
                Text(L("settings.language.system")).tag("")
                Divider()
                ForEach(Loc.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
            .frame(maxWidth: 320)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(L("settings.asciiInput"), isOn: Binding(get: { backend.asciiInput }, set: { backend.setAsciiInput($0) }))
                Text(L("settings.asciiInput.desc")).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("kegPlay \(backend.version)").font(.callout.bold())
                Text(L("settings.about"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button(L("btn.done")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(18).frame(width: 520)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("panel.prompt")
        panel.message = L("panel.message")
        if panel.runModal() == .OK, let url = panel.url { backend.setDataRoot(url) }
    }
}
