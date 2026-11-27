import Foundation
import UIKit
import AudioToolbox

/// Настройки из приложения «Настройки» iPhone → Госномер (Settings.bundle).
enum AppSettings {
    static let defaultServer = "https://nomer.brootai.workers.dev"

    static func register() {
        UserDefaults.standard.register(defaults: [
            "haptics": true,
            "sounds": true,
            "fast_spin": false,
            "server_url": defaultServer
        ])
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        UserDefaults.standard.set("\(v) (\(b))", forKey: "app_version")
    }

    static var serverURL: URL {
        var s = (UserDefaults.standard.string(forKey: "server_url") ?? defaultServer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = defaultServer }
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasPrefix("https://") && !s.hasPrefix("http://") { s = "https://" + s }
        return URL(string: s) ?? URL(string: defaultServer)!
    }

    static var haptics: Bool { UserDefaults.standard.bool(forKey: "haptics") }
    static var sounds: Bool { UserDefaults.standard.bool(forKey: "sounds") }
    static var fastSpin: Bool { UserDefaults.standard.bool(forKey: "fast_spin") }
    static var version: String { UserDefaults.standard.string(forKey: "app_version") ?? "1.0" }

    /// «iPhone · iOS 26.1» — показывается в боте при подтверждении входа
    static var deviceLabel: String {
        var sys = utsname(); uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        return "\(model) · iOS \(UIDevice.current.systemVersion)"
    }
}

enum Haptic {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard AppSettings.haptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() {
        guard AppSettings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func error() {
        guard AppSettings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

/// Щелчки трещотки: системный звук клавиатуры (уважает беззвучный режим iPhone).
enum Ratchet {
    static func tick() {
        if AppSettings.sounds { AudioServicesPlaySystemSound(1104) }
        Haptic.tap(.soft)
    }
    static func stop() {
        if AppSettings.sounds { AudioServicesPlaySystemSound(1105) }
        Haptic.tap(.rigid)
    }
    static func rare() {
        if AppSettings.sounds { AudioServicesPlaySystemSound(1025) }
        Haptic.success()
    }
}
