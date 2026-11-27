import SwiftUI
import UIKit

enum AppTab: Hashable { case spin, collection, profile }

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable { case loading, login, group, ready, failed(String) }

    @Published var phase: Phase = .loading
    @Published var me: Me?
    @Published var config: GameConfig?
    @Published var plates: [Plate] = []
    @Published var platesLoaded = false
    @Published var tab: AppTab = .spin
    @Published var toast: String?
    @Published var alert: String?

    private var toastTask: Task<Void, Never>?

    init() {
        NotificationCenter.default.addObserver(forName: .gosUnauthorized, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.signedOut() }
        }
    }

    func start() async {
        guard API.token != nil else { phase = .login; return }
        await refresh(showLoading: true)
    }

    func refresh(showLoading: Bool = false) async {
        if showLoading { phase = .loading }
        do {
            let r = try await API.get("/api/me")
            me = Me(j: r["me"])
            config = GameConfig(j: r["config"])
            phase = (me?.needGroup ?? false) ? .group : .ready
        } catch let e as APIError where e.status == 401 {
            signedOut()
        } catch {
            if me == nil { phase = .failed((error as? APIError)?.message ?? error.localizedDescription) }
            else { show(error) }
        }
    }

    /// профиль из ответа крутки или другой операции
    func applyMe(_ j: J) {
        guard !j.isNull else { return }
        if let old = me { me = Me(j: old.j.merged(with: j)) } else { me = Me(j: j) }
    }

    func loadCollection() async {
        do {
            let r = try await API.get("/api/collection")
            plates = r["plates"].array.map(Plate.init)
            platesLoaded = true
        } catch { handle(error) }
    }

    /// продажа номеров системе. Возвращает выручку или nil при ошибке
    @discardableResult
    func sell(_ keys: [String]) async -> Double? {
        guard !keys.isEmpty else { return nil }
        do {
            let r = try await API.post("/api/sell", ["keys": keys], idem: true)
            let sum = r["sum"].double ?? 0
            Haptic.success()
            showToast("Продано: \(r["n"].int ?? keys.count) шт. · +\(Fmt.rub(sum))")
            plates.removeAll { keys.contains($0.key) }
            await refresh()
            return sum
        } catch { handle(error); return nil }
    }

    func handle(_ error: Error) {
        if let e = error as? APIError, e.message == "need_group" { phase = .group; return }
        show(error)
    }

    func show(_ error: Error) {
        Haptic.error()
        alert = ServerErr.text(error, config: config, me: me)
    }

    func showToast(_ s: String) {
        toast = s
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.toast = nil }
        }
    }

    func logout() async {
        _ = try? await API.post("/ia/logout")
        signedOut()
    }

    func signedOut() {
        API.token = nil
        me = nil; config = nil; plates = []; platesLoaded = false
        tab = .spin
        phase = .login
    }

    // ссылки в Telegram
    var bot: String { config?.bot ?? "GosnomerGame" }
    func openTelegram(startapp: String? = nil) {
        let tgURL = URL(string: "tg://resolve?domain=\(bot)" + (startapp.map { "&startapp=\($0)" } ?? "&startapp"))!
        let web = URL(string: "https://t.me/\(bot)?startapp" + (startapp.map { "=\($0)" } ?? ""))!
        UIApplication.shared.open(tgURL) { ok in if !ok { UIApplication.shared.open(web) } }
    }
    func openLink(_ s: String) {
        guard let u = URL(string: s) else { return }
        UIApplication.shared.open(u)
    }
}
