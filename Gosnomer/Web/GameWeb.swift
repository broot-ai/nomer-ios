import SwiftUI
import UIKit
import WebKit

/// Одна вкладка игры: страница Mini App внутри приложения + мост к iOS (bridge.js).
@MainActor
final class GameWeb: NSObject, ObservableObject {
    let route: String
    @Published var showBack = false
    @Published var ready = false
    @Published var failed: String?

    private(set) var webView: WKWebView?
    static let pool = WKProcessPool()
    private static let bridgeJS: String = {
        guard let u = Bundle.main.url(forResource: "bridge", withExtension: "js"), let s = try? String(contentsOf: u, encoding: .utf8) else { return "" }
        return s
    }()

    init(route: String) {
        self.route = route
        super.init()
        NotificationCenter.default.addObserver(forName: .gosAppActive, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.eval("typeof refresh === 'function' && refresh().catch(function(){})") }
        }
    }

    func make(dark: Bool) -> WKWebView {
        if let w = webView { return w }
        let cfg = WKWebViewConfiguration()
        cfg.processPool = Self.pool
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let ucc = WKUserContentController()
        ucc.add(WeakHandler(self), name: "gos")
        ucc.addUserScript(WKUserScript(source: "window.__GOS_CFG = \(configJSON(dark: dark));" + Self.bridgeJS,
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = ucc
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = self
        w.uiDelegate = self
        w.isOpaque = false
        w.backgroundColor = .clear
        w.scrollView.backgroundColor = .clear
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.allowsBackForwardNavigationGestures = false
        w.allowsLinkPreview = false
        if #available(iOS 16.4, *) { w.isInspectable = true }
        webView = w
        load()
        return w
    }

    func load() {
        failed = nil
        var c = URLComponents(url: AppSettings.serverURL, resolvingAgainstBaseURL: false)!
        c.path = "/"
        c.queryItems = [URLQueryItem(name: "inapp", value: "1")]
        webView?.load(URLRequest(url: c.url!, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
    }

    private func configJSON(dark: Bool) -> String {
        let u: [String: Any] = Self.user ?? [:]
        let o: [String: Any] = ["token": API.token ?? "", "user": u, "dark": dark, "route": route, "bot": Self.bot]
        let d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
        return String(data: d, encoding: .utf8) ?? "{}"
    }

    /// данные игрока для initDataUnsafe.user (игра показывает имя и аватар до загрузки профиля)
    static var user: [String: Any]?
    static var bot = "GosnomerGame"

    func goBack() { Haptic.tap(); eval("window.__gosBack && window.__gosBack()") }
    func setDark(_ d: Bool) { eval("window.__gosTheme && window.__gosTheme(\(d ? "true" : "false"))") }
    func eval(_ js: String) { guard ready else { return }; webView?.evaluateJavaScript(js, completionHandler: nil) }
}

extension Notification.Name {
    static let gosAppActive = Notification.Name("gosAppActive")
}

/// WKUserContentController держит обработчик сильно — прокладка, чтобы вкладка могла освободиться
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: GameWeb?
    init(_ t: GameWeb) { target = t }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        Task { @MainActor in self.target?.handle(body) }
    }
}

extension GameWeb {
    func handle(_ m: [String: Any]) {
        let t = m["t"] as? String ?? ""
        let id = m["id"] as? Int ?? (m["id"] as? NSNumber)?.intValue ?? 0
        switch t {
        case "ready":
            ready = true
        case "back":
            withAnimation(.snappy) { showBack = (m["v"] as? Bool) ?? false }
        case "haptic":
            guard AppSettings.haptics else { return }
            let s = m["s"] as? String ?? ""
            switch m["k"] as? String {
            case "notify":
                UINotificationFeedbackGenerator().notificationOccurred(s == "error" ? .error : s == "warning" ? .warning : .success)
            case "select":
                UISelectionFeedbackGenerator().selectionChanged()
            default:
                let st: UIImpactFeedbackGenerator.FeedbackStyle = s == "heavy" ? .heavy : s == "medium" ? .medium : s == "rigid" ? .rigid : s == "soft" ? .soft : .light
                UIImpactFeedbackGenerator(style: st).impactOccurred()
            }
        case "open":
            if let s = m["url"] as? String { Self.openExternal(s) }
        case "alert":
            present(title: nil, message: m["message"] as? String ?? "", actions: [("OK", .default, "")]) { [weak self] _ in self?.reply(id, "null") }
        case "confirm":
            present(title: nil, message: m["message"] as? String ?? "", actions: [("Отмена", .cancel, "0"), ("OK", .default, "1")]) { [weak self] v in self?.reply(id, v == "1" ? "true" : "false") }
        case "popup":
            let btns = (m["buttons"] as? [[String: Any]]) ?? []
            var acts: [(String, UIAlertAction.Style, String)] = []
            for b in btns {
                let type = b["type"] as? String ?? "default"
                let bid = b["id"] as? String ?? ""
                var text = b["text"] as? String ?? ""
                var style: UIAlertAction.Style = .default
                switch type {
                case "ok": text = text.isEmpty ? "OK" : text
                case "close": text = text.isEmpty ? "Закрыть" : text; style = .cancel
                case "cancel": text = text.isEmpty ? "Отмена" : text; style = .cancel
                case "destructive": style = .destructive
                default: break
                }
                acts.append((text, style, bid))
            }
            if acts.isEmpty { acts = [("Закрыть", .cancel, "")] }
            // у UIAlertController может быть только одна кнопка-«отмена»
            var seenCancel = false
            acts = acts.map { a in
                if a.1 == .cancel { if seenCancel { return (a.0, .default, a.2) }; seenCancel = true }
                return a
            }
            let title = (m["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            present(title: title, message: m["message"] as? String ?? "", actions: acts) { [weak self] v in
                let js = (try? JSONSerialization.data(withJSONObject: [v])).flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
                self?.reply(id, js)
            }
        default:
            break
        }
    }

    private func reply(_ id: Int, _ jsValue: String) {
        webView?.evaluateJavaScript("window.__gosCb && window.__gosCb(\(id), \(jsValue))", completionHandler: nil)
    }

    private func present(title: String?, message: String, actions: [(String, UIAlertAction.Style, String)], done: @escaping (String) -> Void) {
        Haptic.tap()
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        for x in actions { a.addAction(UIAlertAction(title: x.0, style: x.1) { _ in done(x.2) }) }
        guard let vc = UIApplication.topViewController() else { done(actions.first?.2 ?? ""); return }
        vc.present(a, animated: true)
    }

    static func openExternal(_ s: String) {
        guard let url = URL(string: s) else { return }
        // ссылки t.me открываем сразу в Telegram, если он установлен
        if url.host == "t.me" || url.host == "telegram.me" {
            var c = URLComponents()
            c.scheme = "tg"
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.first == "share" {
                UIApplication.shared.open(url); return
            }
            if let first = parts.first, !first.isEmpty {
                c.host = "resolve"
                var q = [URLQueryItem(name: "domain", value: first)]
                if parts.count > 1 { q.append(URLQueryItem(name: "post", value: parts[1])) }
                q.append(contentsOf: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                if first.hasPrefix("$") || first.hasPrefix("+") { UIApplication.shared.open(url); return }
                c.queryItems = q
                if let tgURL = c.url {
                    UIApplication.shared.open(tgURL) { ok in if !ok { UIApplication.shared.open(url) } }
                    return
                }
            }
        }
        UIApplication.shared.open(url)
    }
}

extension GameWeb: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .allow }
        let scheme = url.scheme ?? ""
        if ["about", "data", "blob"].contains(scheme) { return .allow }
        if (scheme == "http" || scheme == "https"), url.host == AppSettings.serverURL.host { return .allow }
        // встроенные фреймы (например, видео) — внутри
        if let f = action.targetFrame, !f.isMainFrame, scheme == "http" || scheme == "https" { return .allow }
        // чужие сайты, t.me, tg:// и TON-кошельки — во внешнем приложении
        Self.openExternal(url.absoluteString)
        return .cancel
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed = "Не удалось открыть игру. Проверьте интернет или включите VPN."
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { failed = "Связь с игрой прервалась." }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false; webView.reload()
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        ready = false; showBack = false
    }

    // window.open / target=_blank → наружу
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url { Self.openExternal(u.absoluteString) }
        return nil
    }
    // обычные alert / confirm / prompt игры — родные окна iOS
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            present(title: nil, message: message, actions: [("OK", .default, "")]) { _ in c.resume() }
        }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            present(title: nil, message: message, actions: [("Отмена", .cancel, "0"), ("OK", .default, "1")]) { v in c.resume(returning: v == "1") }
        }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in c.resume(returning: nil) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in c.resume(returning: a.textFields?.first?.text) })
            if let vc = UIApplication.topViewController() { vc.present(a, animated: true) } else { c.resume(returning: nil) }
        }
    }
}

extension UIApplication {
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}

/// UIKit-обёртка для SwiftUI
struct WebContainer: UIViewRepresentable {
    let web: GameWeb
    let dark: Bool
    func makeUIView(context: Context) -> WKWebView { web.make(dark: dark) }
    func updateUIView(_ v: WKWebView, context: Context) {}
}

/// Экран вкладки: игра + родная кнопка «Назад» (там, где в Telegram была бы его кнопка)
struct GameTab: View {
    @ObservedObject var web: GameWeb
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: scheme == .dark ? UIColor(red: 0.11, green: 0.11, blue: 0.114, alpha: 1) : UIColor(red: 0.937, green: 0.937, blue: 0.957, alpha: 1))
                    .ignoresSafeArea()
                WebContainer(web: web, dark: scheme == .dark)
                    .opacity(web.ready ? 1 : 0)
                if !web.ready && web.failed == nil {
                    ProgressView().controlSize(.large)
                }
                if let f = web.failed {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text(f).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Повторить") { web.load() }.buttonStyle(.glassProminent)
                    }
                    .padding(32)
                }
            }
            .toolbar {
                if web.showBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { web.goBack() } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Назад")
                    }
                }
            }
            .toolbar(web.showBack ? .visible : .hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: scheme) { _, s in web.setDark(s == .dark) }
    }
}
