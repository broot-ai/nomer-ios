import SwiftUI
import UIKit
import Security

/// Вход: приложение создаёт заявку → открывается бот → игрок жмёт «Войти» → приложение получает токен.
@MainActor
final class LoginFlow: ObservableObject {
    enum Step: Equatable { case idle, starting, waiting, confirm(String), denied, expired, error(String) }
    @Published var state: Step = .idle
    private var nonce = "", secret = "", link = "", tgLink = ""
    private var pollTask: Task<Void, Never>?

    func begin(onToken: @escaping (String) -> Void) {
        pollTask?.cancel()
        state = .starting
        secret = Self.randomHex(32)
        Task {
            do {
                let r = try await API.post("/ia/start", ["s": secret])
                nonce = r["nonce"].string ?? ""
                link = r["link"].string ?? ""
                tgLink = r["tg"].string ?? ""
                guard !nonce.isEmpty else { state = .error("Сервер не выдал код входа"); return }
                state = .waiting
                openBot()
                poll(onToken: onToken)
            } catch {
                state = .error((error as? APIError)?.message ?? error.localizedDescription)
            }
        }
    }

    func openBot() {
        guard let t = URL(string: tgLink) else { return }
        UIApplication.shared.open(t) { [link] ok in
            if !ok, let w = URL(string: link) { UIApplication.shared.open(w) }
        }
    }

    private func poll(onToken: @escaping (String) -> Void) {
        pollTask = Task {
            let started = Date()
            while !Task.isCancelled, Date().timeIntervalSince(started) < 600 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let r = try? await API.get("/ia/poll", ["n": nonce, "s": secret]) else { continue }
                switch r["st"].string {
                case "ok":
                    if let tok = r["token"].string { Haptic.success(); onToken(tok); return }
                case "confirm": state = .confirm(r["user"]["name"].string ?? "")
                case "denied": state = .denied; return
                case "gone": state = .expired; return
                default: break
                }
            }
            if !Task.isCancelled { state = .expired }
        }
    }

    func cancel() { pollTask?.cancel(); state = .idle }

    static func randomHex(_ n: Int) -> String {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return b.map { String(format: "%02x", $0) }.joined()
    }
}

struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var flow = LoginFlow()
    @State private var demoPlate = PlateView.sample("civil")
    @State private var spinTimer: Timer?

    var body: some View {
        ZStack {
            BrandBackground()
            VStack(spacing: 0) {
                Spacer()
                PlateView(kind: "civil", parts: demoPlate)
                    .frame(maxWidth: 300)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                    .padding(.horizontal, 32)
                Text("Госномер")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.top, 28)
                Text("Крути автономера, собирай редкие\nи торгуй с другими игроками")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                Spacer()
                status
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                Button {
                    Haptic.tap(.medium)
                    flow.begin { tok in
                        API.token = tok
                        Task { await model.start() }
                    }
                } label: {
                    Label(buttonTitle, systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .disabled(flow.state == .starting)
                .padding(.horizontal, 24)
                Text("Вход подтверждается в боте @\(model.bot). Пароль не нужен.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .onAppear { startDemo() }
        .onDisappear { spinTimer?.invalidate(); flow.cancel() }
    }

    private var buttonTitle: String {
        switch flow.state {
        case .waiting, .confirm: return "Открыть Telegram ещё раз"
        default: return "Войти через Telegram"
        }
    }

    @ViewBuilder private var status: some View {
        switch flow.state {
        case .idle: EmptyView()
        case .starting:
            ProgressView().tint(.white)
        case .waiting:
            note("hourglass", "Откройте бота и нажмите «Войти». Потом вернитесь сюда — приложение откроется само.")
        case .confirm(let name):
            note("hand.tap.fill", name.isEmpty ? "Нажмите «Войти» в сообщении бота." : "\(name), нажмите «Войти» в сообщении бота.")
        case .denied:
            note("xmark.octagon.fill", "Вход отклонён в боте.")
        case .expired:
            note("clock.badge.exclamationmark", "Время на вход вышло. Нажмите кнопку ещё раз.")
        case .error(let m):
            note("exclamationmark.triangle.fill", m)
        }
    }

    private func note(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    /// на экране входа номер сам «крутится»
    private func startDemo() {
        spinTimer?.invalidate()
        spinTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.snappy) { demoPlate = PlateView.random("civil") }
            }
        }
    }
}

/// Без группы игра закрыта — так решено в игре. Показываем ссылку и кнопку проверки.
struct GroupGateView: View {
    @EnvironmentObject var model: AppModel
    @State private var link: String?
    @State private var checking = false

    var body: some View {
        ZStack {
            BrandBackground()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "person.3.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.white)
                    .padding(26)
                    .glassEffect(.regular, in: .circle)
                Text("Вступите в группу игры")
                    .font(.title2.bold()).foregroundStyle(.white)
                Text("Играть можно только участникам группы «Госномер». Там проходят аукционы, сделки и розыгрыши.")
                    .font(.body).foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center).padding(.horizontal, 28)
                Spacer()
                Button {
                    Haptic.tap()
                    if let l = link ?? model.config?.groupLink { model.openLink(l) } else { model.openTelegram() }
                } label: {
                    Label("Открыть группу", systemImage: "arrow.up.right").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).controlSize(.extraLarge)
                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        if checking { ProgressView() }
                        Text("Я вступил — проверить")
                    }
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass).controlSize(.large)
                .disabled(checking)
                Button("Выйти из аккаунта") { Task { await model.logout() } }
                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
        }
        .task { await fetchLink() }
    }

    private func fetchLink() async {
        if let r = try? await API.get("/api/group/check") {
            if r["ok"].bool { await model.refresh(); return }
            link = r["link"].string.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    private func check() async {
        checking = true; defer { checking = false }
        do {
            let r = try await API.get("/api/group/check")
            if r["ok"].bool { Haptic.success(); await model.refresh() }
            else {
                link = r["link"].string.flatMap { $0.isEmpty ? nil : $0 } ?? link
                Haptic.error()
                model.alert = "Пока не видим вас в группе. Вступите и нажмите ещё раз — Telegram иногда обновляет состав группы с задержкой."
            }
        } catch { model.show(error) }
    }
}
