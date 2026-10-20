import AppKit
import Foundation
import SwiftUI

/// Một game Steam đã cài trong bottle (đọc từ steamapps/appmanifest_<id>.acf).
/// Cảnh báo của "bác sĩ" (scripts/doctor.pl) cho một game: mã phát hiện (khớp mục trên kegplay.com/debug) + mức nặng.
struct GameIssue: Sendable, Equatable {
    let id: String
    let bad: Bool          // true = không chạy được (đỏ); false = có thể có vấn đề (cam)
}

/// Một lần game văng mà bác sĩ đọc log thấy (scripts/doctor.pl --log).
struct CrashReport: Identifiable, Equatable {
    let id = UUID()
    let game: Game
    let finding: String      // mã phát hiện nặng nhất (game-crash, missing-dll, shader-compile-e4002…)
    let detail: String
    let log: String          // đoạn log từ lúc game mở tới lúc văng (đã xoá thông tin riêng)
    var known: Bool { finding != "game-crash" }
}

struct Game: Identifiable, Hashable {
    let id: String          // Steam AppID
    let name: String
    let sizeBytes: Int64
    let ready: Bool         // false = Steam đang tải/cập nhật game này → chưa cho bấm Chơi
    var installDir: String = ""   // steamapps/common/<installDir> — để nhận tiến trình game đang chạy

    var coverURL: URL? { URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/header.jpg") }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }
}

/// Cầu nối giữa giao diện và bộ script của Kegplay (scripts/*.sh).
/// - Mã (scripts, engines, prebuilt) nằm trong app: Contents/Resources/kegplay  → KEGPLAY_ROOT (script tự suy ra).
/// - Dữ liệu (Wine, bottle, game, cache, log) nằm ngoài app                     → KEGPLAY_DATA.
@MainActor
final class Backend: ObservableObject {
    @Published var wineInstalled = false
    @Published var steamInstalled = false
    @Published var steamRunning = false
    @Published var engine = "dxmt"          // công nghệ đang cấu hình cho bottle
    @Published var unblock = false          // bộ vượt chặn Steam Store
    @Published var games: [Game] = []
    @Published var issues: [String: GameIssue] = [:]   // appid → cảnh báo nặng nhất của bác sĩ
    @Published var crash: CrashReport?                 // game vừa văng → dải báo trong cửa sổ
    @Published var busy = false
    @Published var busyTitle = ""
    @Published var busyDetail = ""
    @Published var log: [String] = []
    @Published var alert: String?
    @Published var dataRoot: URL
    @Published var updateVersion: String?    // có bản phát hành mới hơn trên GitHub → hiện dải thông báo
    @Published var asciiInput = InputGuard.enabled   // tự chuyển bộ gõ sang ABC khi vào cửa sổ game
    @Published var language = Loc.override    // "" = theo macOS; đổi → mọi view vẽ lại

    let codeRoot: URL
    let version: String          // hiển thị: "0.1.0 (build 9)"
    let release: String          // số phát hành trong file VERSION: "0.1.0"
    let buildNumber: String
    private var timer: Timer?
    private var doctorKey: String?      // danh sách game đã khám lần trước; đổi thì khám lại
    private var runningGames: [String: (log: URL, offset: UInt64)] = [:]   // appid → log Steam + vị trí lúc game mở
    private var fixedGames: Set<String>?     // game đã tải xong mà app đã xét sửa hiển thị; nil = chưa quét lần nào
    private let inputGuard = InputGuard()

    static let defaultDataRoot = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kegplay")

    init() {
        // Khi phát triển: KEGPLAY_CODE trỏ thẳng thư mục dự án để khỏi build lại app sau mỗi lần sửa script.
        if let dev = ProcessInfo.processInfo.environment["KEGPLAY_CODE"] {
            codeRoot = URL(fileURLWithPath: dev)
        } else {
            codeRoot = Bundle.main.resourceURL!.appendingPathComponent("kegplay")
        }
        if let saved = UserDefaults.standard.string(forKey: "dataRoot"), !saved.isEmpty {
            dataRoot = URL(fileURLWithPath: saved)
        } else {
            dataRoot = Backend.defaultDataRoot
        }
        let release = (try? String(contentsOf: codeRoot.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
        // BUILD: số bản dựng, tools/build-all.sh tăng mỗi lần build
        let build = (try? String(contentsOf: codeRoot.appendingPathComponent("BUILD"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        version = build.isEmpty ? release : "\(release) (build \(build))"
        self.release = release
        buildNumber = build
        inputGuard.start()
        Task { await checkForUpdate() }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Đường dẫn

    var bottle: URL { dataRoot.appendingPathComponent("bottles/steam") }
    var steamDir: URL { bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam") }
    var logsDir: URL { dataRoot.appendingPathComponent("logs") }
    var ready: Bool { wineInstalled && steamInstalled }

    // MARK: - Trang web & bản mới

    static let repoSlug = "tiengdung90/kegplay"
    static let releasesPage = URL(string: "https://github.com/\(repoSlug)/releases/latest")!

    /// Trang lịch sử gỡ lỗi / cách xử lý sự cố trên web. Kèm số bản + ngôn ngữ để trang hiện đúng mục
    /// (không kèm thông tin nào về người dùng hay máy).
    var helpURL: URL {
        var c = URLComponents(string: "https://kegplay.com/debug")!
        c.queryItems = [URLQueryItem(name: "v", value: release), URLQueryItem(name: "b", value: buildNumber),
                        URLQueryItem(name: "lang", value: Loc.current)]
        return c.url!
    }

    func openHelp() { NSWorkspace.shared.open(helpURL) }
    /// Mở đúng mục trên trang gỡ lỗi (kegplay.com/debug#<mã>)
    func openHelp(anchor: String) {
        var c = URLComponents(url: helpURL, resolvingAgainstBaseURL: false)!
        c.fragment = anchor
        NSWorkspace.shared.open(c.url ?? helpURL)
    }
    func openReleases() { NSWorkspace.shared.open(Backend.releasesPage) }

    /// Hỏi GitHub bản phát hành mới nhất (địa chỉ công khai, không gửi dữ liệu gì). Lỗi/mất mạng/chưa có bản
    /// phát hành nào → im lặng.
    func checkForUpdate() async {
        guard let url = URL(string: "https://api.github.com/repos/\(Backend.repoSlug)/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        if Backend.isNewer(latest, than: release) { updateVersion = latest }
    }

    /// So số phiên bản kiểu 0.10.2 theo từng phần (không so chuỗi: "0.10" > "0.9").
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func setAsciiInput(_ on: Bool) {
        InputGuard.enabled = on
        asciiInput = on
    }

    func setLanguage(_ code: String) {
        Loc.override = code
        language = code
    }

    func setDataRoot(_ url: URL) {
        dataRoot = url
        UserDefaults.standard.set(url.path, forKey: "dataRoot")
        refresh()
    }

    // MARK: - Trạng thái (rẻ: chỉ đọc file + ps, không gọi wine)

    func refresh() {
        let fm = FileManager.default
        let data = dataRoot, bottle = self.bottle, steamDir = self.steamDir
        let runtime = data.appendingPathComponent("runtime")
        let wine = ((try? fm.contentsOfDirectory(atPath: runtime.path)) ?? [])
            .contains { $0.hasPrefix("wine-devel-") && fm.isExecutableFile(atPath: runtime.appendingPathComponent("\($0)/bin/wine").path) }
        let steam = fm.fileExists(atPath: steamDir.appendingPathComponent("steam.exe").path)
            || fm.fileExists(atPath: steamDir.appendingPathComponent("Steam.exe").path)
        let eng = (try? String(contentsOf: bottle.appendingPathComponent(".kegplay_engine"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "dxmt"
        let unb = fm.fileExists(atPath: bottle.appendingPathComponent(".kegplay_pac").path)
        let found = Backend.scanGames(steamDir: steamDir)
        let marker = steamDir.appendingPathComponent("steam.exe").path.lowercased()
        let serverMarker = data.appendingPathComponent("runtime").path.lowercased()

        Task.detached {
            // Steam do kegPlay mở hiện trong ps bằng đường dẫn Unix (marker). Steam do một game tự gọi lên
            // (vd file khởi chạy của game chạy "steam.exe steam://run/…") lại hiện bằng đường dẫn Windows → phải nhận cả
            // trường hợp đó, miễn là wineserver của đúng thư mục dữ liệu này đang chạy. Không thì app báo "Sẵn sàng"
            // trong khi script từ chối mở vì Steam đã chạy.
            let lines = Backend.processList().map { $0.lowercased() }
            let ownServer = lines.contains { $0.contains(serverMarker) && $0.contains("wineserver") }
            let running = lines.contains { $0.contains(marker) }
                || (ownServer && lines.contains { $0.contains("\\steam\\steam.exe") })
            // game đang chạy = có tiến trình Windows nằm trong steamapps\common\<thư mục game>\
            let playing = Set(found.filter { g in
                !g.installDir.isEmpty && lines.contains { $0.contains("\\steamapps\\common\\" + g.installDir.lowercased() + "\\") }
            }.map(\.id))
            await MainActor.run {
                self.wineInstalled = wine
                self.steamInstalled = steam
                if !self.busy { self.engine = (eng == "dxvk") ? "dxvk" : "dxmt" }
                self.unblock = unb
                self.games = found
                self.steamRunning = running
                self.fixNewGames(found)
                self.runDoctor(found)
                self.watchGames(playing, found)
            }
        }
    }

    /// Game vừa tải xong trong lúc app đang mở → cài bản sửa riêng của game đó (nếu có) ngay, không chờ lần mở Steam sau.
    /// Lần quét đầu chỉ ghi nhận: các game có sẵn đã được run-steam.sh / launch-game.sh lo.
    private func fixNewGames(_ found: [Game]) {
        let ready = Set(found.filter(\.ready).map(\.id))
        guard let known = fixedGames else { fixedGames = ready; return }
        guard !busy else { return }             // đang chạy việc khác → để lượt quét sau
        let fresh = ready.subtracting(known)
        fixedGames = ready
        guard !fresh.isEmpty else { return }
        Task { for id in fresh.sorted() { _ = await runScript("apply-fixes.sh", [id]) } }
    }

    /// Khám các game đã tải xong (đọc file chạy của game: DirectX 12, DirectX 9, DirectDraw, anti-cheat…) mỗi khi
    /// danh sách đổi. Chỉ giữ cảnh báo (warn/bad) — game ổn thì thẻ không hiện gì thêm. Chỉ đọc, ~0,2 giây.
    private func runDoctor(_ found: [Game]) {
        let key = found.filter(\.ready).map(\.id).sorted().joined(separator: ",")
        guard key != doctorKey else { return }
        doctorKey = key
        let script = codeRoot.appendingPathComponent("scripts/doctor.sh").path
        let data = dataRoot.path
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script]
            p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
                             "KEGPLAY_DATA": data, "LANG": "en_US.UTF-8"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            var res: [String: GameIssue] = [:]
            for line in out.split(separator: "\n") {
                let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard c.count >= 4, c[0] != "-", c[2] == "warn" || c[2] == "bad" else { continue }
                let issue = GameIssue(id: c[3], bad: c[2] == "bad")
                if let old = res[c[0]], old.bad || !issue.bad { continue }
                res[c[0]] = issue
            }
            let result = res
            await MainActor.run { self.issues = result }
        }
    }

    /// Khám SAU khi lỗi: nhớ vị trí cuối log Steam lúc game bắt đầu chạy; game biến mất thì đọc phần log từ đó
    /// (doctor.pl --log). Có dấu hiệu văng / thiếu DLL / lỗi shader → hiện dải báo, kèm nút xem cách xử lý hoặc gửi báo cáo.
    private func watchGames(_ playing: Set<String>, _ found: [Game]) {
        for id in playing where runningGames[id] == nil {
            if let log = latestSteamLog() {
                let size = (try? FileManager.default.attributesOfItem(atPath: log.path)[.size] as? UInt64) ?? 0
                runningGames[id] = (log, size ?? 0)
            }
        }
        for (id, start) in runningGames where !playing.contains(id) {
            runningGames[id] = nil
            guard let game = found.first(where: { $0.id == id }) else { continue }
            let script = codeRoot.appendingPathComponent("scripts/doctor.sh").path
            let data = dataRoot.path
            Task.detached {
                // chờ Wine ghi nốt log
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [script, "--log", start.log.path, String(start.offset)]
                p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
                                 "KEGPLAY_DATA": data, "LANG": "en_US.UTF-8"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                guard (try? p.run()) != nil else { return }
                let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                p.waitUntilExit()
                let rows = out.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
                    .filter { $0.count >= 5 && $0[2] == "bad" }
                guard !rows.isEmpty else { return }
                // ưu tiên nguyên nhân cụ thể (thiếu DLL, lỗi shader) hơn "văng" chung chung
                let pick = rows.first { $0[3] != "game-crash" } ?? rows[0]
                let log = Backend.logExcerpt(start.log, from: start.offset)
                await MainActor.run {
                    self.crash = CrashReport(game: game, finding: pick[3], detail: pick[4], log: log)
                }
            }
        }
    }

    private func latestSteamLog() -> URL? {
        let dir = dataRoot.appendingPathComponent("logs")
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.range(of: #"^steam-\d{8}-\d{6}\.log$"#, options: .regularExpression) != nil }.sorted()   // không lấy steam-bootstrap.log
        return files.last.map { dir.appendingPathComponent($0) }
    }

    /// 60 dòng cuối của log kể từ vị trí `from`, đã xoá tên tài khoản và đường dẫn thư mục người dùng.
    nonisolated static func logExcerpt(_ url: URL, from: UInt64) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        try? h.seek(toOffset: from)
        let text = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(60).joined(separator: "\n")
        return sanitize(String(lines.suffix(4000)))
    }

    nonisolated static func sanitize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let user = NSUserName()
        if user.count >= 3 { t = t.replacingOccurrences(of: user, with: "<user>", options: .caseInsensitive) }
        return t
    }

    /// Trang tạo Issue trên GitHub, đã điền sẵn. Người dùng xem lại và tự bấm gửi — kegPlay không tự gửi gì.
    func reportURL(_ r: CrashReport?) -> URL {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let chip = String(cString: buf)
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let title = r.map { "[\($0.game.name)] \($0.finding)" } ?? "Problem report"
        var body = """
        **kegPlay** \(version) · engine \(engine.uppercased())
        **macOS** \(os) · **Chip** \(chip)

        """
        if let r {
            body += """
            **Game** \(r.game.name) (AppID \(r.game.id))
            **kegPlay detected** `\(r.finding)` \(r.detail)

            """
        }
        body += """
        **What happened** (please describe what you did and what you saw):


        **Log**
        ```
        \(r?.log ?? Backend.sanitize(log.suffix(60).joined(separator: "\n")))
        ```
        """
        var c = URLComponents(string: "https://github.com/\(Backend.repoSlug)/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        return c.url!
    }

    func openReport(_ r: CrashReport?) { NSWorkspace.shared.open(reportURL(r)) }

    nonisolated static func processList() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "command"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// Đọc steamapps/appmanifest_*.acf (định dạng VDF: "khoá"  "giá trị").
    nonisolated static func scanGames(steamDir: URL) -> [Game] {
        let apps = steamDir.appendingPathComponent("steamapps")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: apps.path) else { return [] }
        var out: [Game] = []
        for f in files where f.hasPrefix("appmanifest_") && f.hasSuffix(".acf") {
            guard let text = try? String(contentsOf: apps.appendingPathComponent(f), encoding: .utf8) else { continue }
            func value(_ key: String) -> String? {
                guard let r = text.range(of: "\"\(key)\"") else { return nil }
                let rest = text[r.upperBound...]
                guard let a = rest.firstIndex(of: "\"") else { return nil }
                let after = rest[rest.index(after: a)...]
                guard let b = after.firstIndex(of: "\"") else { return nil }
                return String(after[..<b])
            }
            guard let id = value("appid"), let name = value("name") else { continue }
            // 228980 = "Steamworks Common Redistributables" — không phải game
            if id == "228980" { continue }
            // StateFlags: 4 = đã cài đủ; có bit 2 (cần cập nhật) hoặc thiếu bit 4 = đang tải/cập nhật.
            // Không hiện % vì Steam chỉ thỉnh thoảng mới ghi BytesDownloaded vào file này (lệch xa thực tế).
            let flags = Int(value("StateFlags") ?? "0") ?? 0
            out.append(Game(id: id, name: name, sizeBytes: Int64(value("SizeOnDisk") ?? "0") ?? 0,
                            ready: flags & 4 != 0 && flags & 2 == 0, installDir: value("installdir") ?? ""))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Chạy script

    private func appendLog(_ chunk: String) {
        // curl in thanh tiến độ bằng \r — tách cả \r lẫn \n, dòng tiến độ chỉ hiện ở busyDetail
        for raw in chunk.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.allSatisfy({ "#=-O.% 0123456789".contains($0) }) {
                if let pct = trimmed.split(separator: " ").last, pct.hasSuffix("%") { busyDetail = L("busy.downloading", String(pct)) }
                continue
            }
            log.append(line)
            busyDetail = trimmed
        }
        if log.count > 600 { log.removeFirst(log.count - 600) }
    }

    /// Chạy 1 script trong scripts/, đẩy output vào log. Trả về mã thoát.
    private func runScript(_ name: String, _ args: [String] = [], env extra: [String: String] = [:]) async -> Int32 {
        let script = codeRoot.appendingPathComponent("scripts/\(name)").path
        var env: [String: String] = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "TERM": "dumb",
            "LANG": "en_US.UTF-8",
            "KEGPLAY_DATA": dataRoot.path,
        ]
        for (k, v) in extra { env[k] = v }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script] + args
        p.environment = env
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            let s = String(decoding: d, as: UTF8.self)
            Task { @MainActor in self.appendLog(s) }
        }
        log.append("▶ \(name) \(args.joined(separator: " "))")
        return await withCheckedContinuation { cont in
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: proc.terminationStatus)
            }
            do { try p.run() } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in self.log.append(L("err.cannotRun", name, error.localizedDescription)) }
                cont.resume(returning: 127)
            }
        }
    }

    /// Chạy lần lượt các bước; dừng ở bước lỗi và báo cho người dùng.
    private func perform(_ title: String, _ steps: [(String, [String], [String: String])]) async -> Bool {
        guard !busy else { return false }
        busy = true; busyTitle = title; busyDetail = L("busy.working")
        defer { busy = false; refresh() }
        try? FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        for (name, args, env) in steps {
            let code = await runScript(name, args, env: env)
            if code != 0 {
                let tail = log.suffix(4).joined(separator: "\n")
                alert = L("alert.failed", title, name, String(code)) + "\n\n" + tail
                return false
            }
        }
        return true
    }

    // MARK: - Hành động

    func install() async {
        _ = await perform(L("first.title"), [
            ("setup.sh", [], [:]),
            ("install-steam.sh", [], [:]),
            ("use-engine.sh", ["dxmt"], [:]),
        ])
    }

    func openSteam(engine want: String) async {
        _ = await perform(L("busy.openSteam", want.uppercased()), [
            ("use-engine.sh", [want], [:]),
            ("run-steam.sh", [], [:]),
        ])
    }

    func play(_ game: Game, engine want: String) async {
        _ = await perform(L("busy.play", game.name), [
            ("use-engine.sh", [want], [:]),
            ("launch-game.sh", [game.id], [:]),
        ])
    }

    func stop() async {
        _ = await perform(L("busy.stop"), [("stop.sh", [], [:])])
    }

    func setUnblock(_ on: Bool) async {
        _ = await perform(on ? L("busy.unblockOn") : L("busy.unblockOff"), [("proxy.sh", [on ? "on" : "off"], [:])])
    }

    func openLogs() {
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(logsDir)
    }

    func revealData() { NSWorkspace.shared.open(dataRoot) }
}
