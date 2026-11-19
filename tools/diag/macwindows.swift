// Liệt kê các cửa sổ Wine đang hiện trên màn hình Mac (kích thước, vị trí, lớp) + độ phân giải hiện tại và các chế độ
// màn hình Mac hỗ trợ. Dùng khi cần biết cửa sổ game THẬT SỰ to bao nhiêu mà không chụp được màn hình.
//   swift tools/diag/macwindows.swift
import CoreGraphics
import Foundation
let d = CGMainDisplayID()
if let c = CGDisplayCopyDisplayMode(d) { print("Current display mode: \(c.width)x\(c.height) (pixels: \(c.pixelWidth)x\(c.pixelHeight))") }
let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
var seen = Set<String>()
let modes = (CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode] ?? []).map { "\($0.width)x\($0.height)" }.filter { seen.insert($0).inserted }
print("Available modes:", modes.joined(separator: " "))
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    guard ((w["kCGWindowOwnerName"] as? String) ?? "").lowercased().contains("wine"), let b = w["kCGWindowBounds"] as? [String: Any] else { continue }
    print("Wine window, PID \(w["kCGWindowOwnerPID"] ?? 0): \(b["Width"] ?? 0)x\(b["Height"] ?? 0) at (\(b["X"] ?? 0),\(b["Y"] ?? 0)), layer \(w["kCGWindowLayer"] ?? 0)")
}
