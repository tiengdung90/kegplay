import Foundation

/// Đa ngôn ngữ cho giao diện. Chuỗi nằm ở Contents/Resources/<mã>.lproj/Localizable.strings
/// (sinh bởi tools/make-localizations.py). Mặc định theo ngôn ngữ macOS; người dùng chọn tay trong Cài đặt.
enum Loc {
    /// (mã .lproj, tên bản ngữ) — cùng thứ tự với LANGS trong make-localizations.py
    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("vi", "Tiếng Việt"), ("zh-Hans", "简体中文"), ("ja", "日本語"), ("ko", "한국어"),
        ("es", "Español"), ("pt-BR", "Português (Brasil)"), ("de", "Deutsch"), ("fr", "Français"),
        ("ru", "Русский"), ("tr", "Türkçe"), ("id", "Bahasa Indonesia"), ("th", "ไทย"),
    ]

    /// "" = theo macOS
    static var override: String = UserDefaults.standard.string(forKey: "appLanguage") ?? "" {
        didSet { UserDefaults.standard.set(override, forKey: "appLanguage"); chosen = load(override) }
    }

    private static var chosen: Bundle? = load(override)
    private static let english: Bundle? = load("en")

    private static func load(_ code: String) -> Bundle? {
        guard !code.isEmpty, let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// Mã ngôn ngữ đang hiển thị (chọn tay, hoặc theo macOS)
    static var current: String {
        override.isEmpty ? (Bundle.main.preferredLocalizations.first ?? "en") : override
    }

    static func string(_ key: String) -> String {
        let missing = "\u{1}"
        let s = (chosen ?? .main).localizedString(forKey: key, value: missing, table: nil)
        if s != missing { return s }
        return english?.localizedString(forKey: key, value: key, table: nil) ?? key
    }
}

/// Lấy chuỗi theo khoá; có tham số thì điền vào các `%@` theo thứ tự.
func L(_ key: String, _ args: String...) -> String {
    let format = Loc.string(key)
    return args.isEmpty ? format : String(format: format, arguments: args)
}
