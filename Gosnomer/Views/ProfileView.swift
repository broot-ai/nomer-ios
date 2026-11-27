import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @State private var claiming = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let me = model.me {
                    VStack(spacing: 16) {
                        header(me)
                        money(me)
                        daily(me)
                        stats(me)
                        more
                        Text("Госномер для iPhone · версия \(AppSettings.version)")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Профиль")
            .confirmationDialog("Выйти из аккаунта на этом iPhone?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { Task { await model.logout() } }
            } message: { Text("Номера и баланс останутся в игре. Войти снова можно через бота.") }
        }
    }

    private func header(_ me: Me) -> some View {
        VStack(spacing: 10) {
            AsyncImage(url: me.photo) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Text(String(me.name.prefix(1))).font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.gradient)
            }
            .frame(width: 96, height: 96)
            .clipShape(.circle)
            .overlay(alignment: .bottomTrailing) {
                Text("\(me.level)")
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 30, minHeight: 30)
                    .background(Color.accentColor, in: .circle)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
            }
            HStack(spacing: 6) {
                Text(me.name).font(.title2.bold())
                if me.vip { Text("VIP").font(.caption.weight(.heavy)).padding(.horizontal, 6).padding(.vertical, 2).background(.yellow, in: .capsule).foregroundStyle(.black) }
            }
            if let u = me.username { Text("@" + u).font(.subheadline).foregroundStyle(.secondary) }
            VStack(spacing: 6) {
                ProgressView(value: me.levelProgress).tint(.accentColor)
                Text("Уровень \(me.level) · \(Fmt.num(me.xp - me.xpFrom)) из \(Fmt.num(me.xpTo - me.xpFrom)) опыта")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func money(_ me: Me) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Баланс").font(.caption).foregroundStyle(.secondary)
                    if me.hideBal {
                        Label("Баланс скрыт", systemImage: "eye.slash").font(.title3.bold())
                    } else {
                        Text(Fmt.rub(me.balance)).font(.title2.bold().monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Звёзды игры").font(.caption).foregroundStyle(.secondary)
                    Text("\(me.starBal) ⭐").font(.title3.bold().monospacedDigit())
                }
            }
            let curs: [String] = me.wallets.filter { $0.value != 0 }.keys.sorted()
            if !curs.isEmpty {
                Divider()
                HStack(spacing: 14) {
                    ForEach(curs, id: \.self) { cur in
                        VStack(spacing: 2) {
                            Text(Fmt.num(me.wallets[cur] ?? 0)).font(.subheadline.weight(.semibold).monospacedDigit())
                            Text(model.config?.fxSymbol(cur) ?? cur).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func daily(_ me: Me) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "gift.fill").font(.title2).foregroundStyle(.pink)
                .frame(width: 44, height: 44).glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Награда дня").font(.headline)
                if me.canDaily {
                    Text(me.streak > 0 ? "Серия: \(me.streak) дн. подряд" : "Заходите каждый день — награда растёт").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Следующая — \(me.nextDaily.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if me.canDaily {
                Button {
                    Task { await claim() }
                } label: { if claiming { ProgressView() } else { Text("Забрать") } }
                    .buttonStyle(.glassProminent)
                    .disabled(claiming)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func stats(_ me: Me) -> some View {
        let s = me.stats
        let items: [StatItem] = [
            StatItem(icon: "dice", title: "Круток", value: Fmt.num(Double(me.spins))),
            StatItem(icon: "rectangle.stack", title: "Номеров", value: Fmt.num(s["plates"].double ?? 0)),
            StatItem(icon: "car.side", title: "Машин", value: Fmt.num(me.j["nCars"].double ?? 0)),
            StatItem(icon: "sparkles", title: "Эпических", value: Fmt.num(s["epic"].double ?? 0)),
            StatItem(icon: "crown", title: "Легендарных", value: Fmt.num(s["leg"].double ?? 0)),
            StatItem(icon: "flame", title: "Мифических", value: Fmt.num(s["myth"].double ?? 0)),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(items) { it in
                VStack(spacing: 4) {
                    Image(systemName: it.icon).font(.subheadline).foregroundStyle(.secondary)
                    Text(it.value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                    Text(it.title).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        }
    }

    private var more: some View {
        VStack(spacing: 0) {
            row("paperplane.fill", "Гараж, рынок, аукционы, гонки", "Пока в игре в Telegram") { model.openTelegram() }
            Divider().padding(.leading, 52)
            row("gearshape.fill", "Настройки приложения", "Вибрация, звук, скорость крутки") {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
            Divider().padding(.leading, 52)
            row("questionmark.bubble.fill", "Поддержка", model.config?.owner ?? "") {
                let o = (model.config?.owner ?? "@Verifure").replacingOccurrences(of: "@", with: "")
                model.openLink("https://t.me/\(o)")
            }
            Divider().padding(.leading, 52)
            row("rectangle.portrait.and.arrow.right", "Выйти", nil, destructive: true) { confirmLogout = true }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func row(_ icon: String, _ title: String, _ sub: String?, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); action() } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.body).frame(width: 24).foregroundStyle(destructive ? Color.red : Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(destructive ? Color.red : Color.primary)
                    if let sub, !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if !destructive { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func claim() async {
        claiming = true; defer { claiming = false }
        do {
            let r = try await API.post("/api/daily", [:], idem: true)
            Haptic.success()
            model.showToast("🎁 Награда дня: +\(Fmt.rub(r["reward"].double ?? 0))")
            await model.refresh()
        } catch { model.handle(error) }
    }
}

struct StatItem: Identifiable {
    let icon: String, title: String, value: String
    var id: String { title }
}
