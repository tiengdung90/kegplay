import AppKit
import Carbon

/// Tự chuyển bộ gõ sang bàn phím Latin (ABC) khi một cửa sổ Wine của Kegplay lên trước, trả lại bộ gõ cũ khi rời đi.
///
/// Vì sao: bộ gõ tiếng Việt (Telex/VNI) hay bộ gõ CJK giữ phím lại để ghép chữ. Trong game, W/A/S/D bị coi là
/// đang gõ văn bản → Wine hiện ô chữ trắng ở góc màn hình, phím tới game chậm hoặc mất.
/// Chỉ đổi đúng lúc cửa sổ Wine được kích hoạt; người dùng vẫn tự đổi lại bộ gõ trong Steam/game nếu muốn gõ có dấu.
/// Làm ở app (không vá Wine) nên có tác dụng với cả DXMT lẫn DXVK — đổi lại, app phải đang mở.
@MainActor
final class InputGuard {
    static let defaultsKey = "asciiInput"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private var saved: TISInputSource?      // bộ gõ của người dùng trước khi vào cửa sổ Wine
    private var observer: NSObjectProtocol?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let path = app?.executableURL?.path ?? ""
            Task { @MainActor in self?.activated(isWine: InputGuard.isKegplayWine(path)) }
        }
    }

    /// Tiến trình Wine của Kegplay: macOS ghi đường dẫn chạy là <dữ liệu>/runtime/wine-…/lib/wine/x86_64-unix/wine
    /// (không phải …/bin/wine), nên chỉ so phần "/runtime/wine-".
    nonisolated static func isKegplayWine(_ path: String) -> Bool {
        path.contains("/runtime/wine-")
    }

    private func activated(isWine: Bool) {
        if isWine {
            guard InputGuard.enabled, saved == nil else { return }
            guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let latin = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
                  InputGuard.id(of: current) != InputGuard.id(of: latin) else { return }
            if TISSelectInputSource(latin) == noErr { saved = current }
        } else if let previous = saved {
            TISSelectInputSource(previous)
            saved = nil
        }
    }

    private static func id(of source: TISInputSource) -> String {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
