import SwiftUI

struct SpinView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("spin_kind") private var kind = "civil"
    @AppStorage("spin_tier") private var tier = 0
    @AppStorage("spin_count") private var count = 1

    @State private var shown: [String: String] = PlateView.sample("civil")
    @State private var shownKind = "civil"
    @State private var placeholder = true
    @State private var spinning = false
    @State private var results: [Plate] = []
    @State private var best: Plate?
    @State private var drum: Task<Void, Never>?
    @State private var selling: Set<String> = []

    private var cfg: GameConfig? { model.config }
    private var info: KindInfo? { cfg?.kind(kind) }
    private var currency: String? { info.flatMap { cfg?.currency($0.country) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    kindPicker
                    plateCard
                    controls
                    if !results.isEmpty { resultList }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background(alignment: .top) {
                LinearGradient(colors: [Color.accentColor.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 380).ignoresSafeArea()
            }
            .navigationTitle("Крутка")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { balanceChip }
            }
        }
        .onAppear { syncPlaceholder() }
        .onChange(of: kind) { _, _ in if !spinning { results = []; best = nil; syncPlaceholder() } }
    }

    // MARK: верх

    private var balanceChip: some View {
        Group {
            if let me = model.me {
                if let cur = currency {
                    Text(Fmt.num(me.wallets[cur] ?? 0) + " " + (cfg?.fxSymbol(cur) ?? cur))
                } else if me.hideBal {
                    Label("Скрыт", systemImage: "eye.slash")
                } else {
                    Text(Fmt.rub(me.balance))
                }
            }
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .contentTransition(.numericText())
        .animation(.snappy, value: model.me?.balance)
        .padding(.horizontal, 4)
    }

    private var kindPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(cfg?.kinds ?? []) { k in
                            let sel = k.id == kind
                            Button {
                                guard !spinning else { return }
                                Haptic.tap()
                                withAnimation(.snappy) { kind = k.id }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(cfg?.flag(k.country) ?? "")
                                    Text(k.name).font(.subheadline.weight(sel ? .bold : .medium))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .foregroundStyle(sel ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(sel ? .regular.tint(Color.accentColor).interactive() : .regular.interactive(), in: .capsule)
                            .id(k.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .onAppear { proxy.scrollTo(kind, anchor: .center) }
        }
    }

    // MARK: номер

    private var plateCard: some View {
        VStack(spacing: 14) {
            PlateView(kind: shownKind, parts: shown, glow: best.flatMap { $0.rarity > 0 ? Rarity.color($0.rarity) : nil })
                .opacity(placeholder ? 0.45 : 1)
                .frame(maxWidth: shownKind == "moto" || shownKind == "tractor" ? 210 : CGFloat.infinity)
                .padding(.horizontal, 6)
                .animation(.snappy(duration: 0.12), value: shown)
            Group {
                if let b = best, !spinning {
                    HStack(spacing: 8) {
                        Circle().fill(Rarity.color(b.rarity)).frame(width: 10, height: 10)
                        Text(cfg?.rarityName(b.rarity) ?? "").font(.headline).foregroundStyle(Rarity.color(b.rarity))
                        Text("·").foregroundStyle(.secondary)
                        Text("оценка " + money(b.value)).font(.headline.monospacedDigit())
                    }
                } else if spinning {
                    Text("Крутим барабан…").font(.headline).foregroundStyle(.secondary)
                } else {
                    Text(info.map { "\($0.name) · \(cfg?.countryName($0.country) ?? "")" } ?? " ").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(height: 24)
            if let b = best, !spinning, results.count == 1 {
                HStack(spacing: 10) {
                    Button {
                        Task { await sell([b.key]) }
                    } label: { Label("Продать", systemImage: "rublesign.circle").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass).controlSize(.large)
                        .disabled(selling.contains(b.key))
                    Button {
                        Haptic.tap(); withAnimation(.snappy) { results = []; best = nil; syncPlaceholder() }
                    } label: { Label("Оставить", systemImage: "checkmark").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass).controlSize(.large)
                }
                if !b.tags.isEmpty {
                    Text(b.tags.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    // MARK: настройки крутки

    private var controls: some View {
        VStack(spacing: 14) {
            if let tiers = cfg?.tiers, !tiers.isEmpty {
                Picker("Уровень", selection: $tier) {
                    ForEach(0..<tiers.count, id: \.self) { i in Text(tiers[i].name).tag(i) }
                }
                .pickerStyle(.segmented)
                .disabled(spinning)
            }
            oddsRow
            Picker("Количество", selection: $count) {
                Text("×1").tag(1); Text("×5").tag(5); Text("×10").tag(10)
            }
            .pickerStyle(.segmented)
            .disabled(spinning)

            Button { spin() } label: {
                HStack(spacing: 10) {
                    if spinning { ProgressView().tint(.white) }
                    Text(spinning ? "Крутим…" : "Крутить ×\(count)")
                    if !spinning { Text("· " + priceText).monospacedDigit() }
                }
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .disabled(spinning || cfg?.maintenance == true)

            if cfg?.maintenance == true {
                Label("Технические работы — крутки временно недоступны", systemImage: "wrench.and.screwdriver")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if let me = model.me {
                Text("Гараж номеров: \(me.garageUsed) из \(me.garageCap) · до удачи \(me.j["toLuck"].int ?? 0) круток")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    /// шансы редкости для выбранного вида и уровня — данные с сервера, те же, что в игре
    private var oddsRow: some View {
        let odds = cfg?.odds(kind, tier) ?? []
        let maxR = info?.max ?? 5
        return VStack(alignment: .leading, spacing: 6) {
            Text("Шансы").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<odds.count, id: \.self) { r in
                        let pr = odds[r]
                        if r <= maxR && pr > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(Rarity.color(r)).frame(width: 7, height: 7)
                                Text(cfg?.rarityName(r) ?? "").font(.caption2)
                                Text(Fmt.percent(pr)).font(.caption2.weight(.bold).monospacedDigit())
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Rarity.color(r).opacity(0.13), in: .capsule)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: результаты ×5 / ×10

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Выпало").font(.title3.bold())
                Spacer()
                let commons = results.filter { $0.rarity == 0 }
                if commons.count > 1 {
                    Button("Продать обычные (\(commons.count))") { Task { await sell(commons.map(\.key)) } }
                        .buttonStyle(.glass).controlSize(.small)
                }
            }
            ForEach(results) { p in
                HStack(spacing: 12) {
                    PlateView(kind: p.kind, parts: p.parts)
                        .frame(width: p.kind == "moto" || p.kind == "tractor" ? 64 : 150)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cfg?.rarityName(p.rarity) ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(Rarity.color(p.rarity))
                        Text(money(p.value)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task { await sell([p.key]) }
                    } label: {
                        if selling.contains(p.key) { ProgressView() } else { Image(systemName: "rublesign") }
                    }
                    .buttonStyle(.glass)
                    .disabled(selling.contains(p.key))
                    .accessibilityLabel("Продать")
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }

    // MARK: логика

    private func money(_ v: Double) -> String {
        if let cur = currency { return Fmt.num(v) + " ₽" + " ≈ " + Fmt.num((v / (cfg?.fxRate(cur) ?? 1)).rounded()) + " " + (cfg?.fxSymbol(cur) ?? cur) }
        return Fmt.rub(v)
    }

    private var priceText: String {
        let one = cfg?.price(kind, tier) ?? 0
        if let cur = currency {
            let local = (one / (cfg?.fxRate(cur) ?? 1)).rounded(.up)
            return Fmt.num(local * Double(count)) + " " + (cfg?.fxSymbol(cur) ?? cur)
        }
        return Fmt.rub(one * Double(count))
    }

    private func syncPlaceholder() {
        shownKind = kind
        shown = PlateView.sample(kind)
        placeholder = true
    }

    private func spin() {
        guard !spinning else { return }
        let k = kind, t = tier, n = count
        Haptic.tap(.medium)
        withAnimation(.snappy) { spinning = true; results = []; best = nil }
        shownKind = k
        placeholder = false
        // барабан крутится, пока ждём ответ сервера
        drum?.cancel()
        drum = Task { @MainActor in
            var i = 0
            while !Task.isCancelled {
                shown = PlateView.random(k)
                if i % 2 == 0 { Ratchet.tick() }
                i += 1
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
        }
        Task { @MainActor in
            do {
                let r = try await API.post("/api/spin", ["kind": k, "tier": t, "count": n], idem: true)
                let plates = r["results"].array.map(Plate.init)
                guard let top = plates.max(by: { ($0.rarity, $0.value) < ($1.rarity, $1.value) }) else { throw APIError(message: "Пустой ответ сервера", status: 0) }
                if !AppSettings.fastSpin { try? await Task.sleep(nanoseconds: 450_000_000) }
                drum?.cancel()
                // символы останавливаются слева направо
                let order = PlateView.revealOrder(top.kind, top.parts)
                let step: UInt64 = AppSettings.fastSpin ? 35_000_000 : UInt64(1_300_000_000 / max(1, order.count))
                for i in 0...order.count {
                    var j = 0
                    let until = Date().addingTimeInterval(Double(step) / 1e9)
                    while Date() < until {
                        shown = PlateView.scramble(top.kind, top.parts, revealed: i)
                        if j % 2 == 0 && !AppSettings.fastSpin { Ratchet.tick() }
                        j += 1
                        try? await Task.sleep(nanoseconds: 45_000_000)
                    }
                    if i > 0 { Ratchet.stop() }
                }
                shown = top.parts
                if top.rarity >= 3 { Ratchet.rare() } else { Haptic.success() }
                model.applyMe(r["me"])
                model.platesLoaded = false
                withAnimation(.bouncy) {
                    best = top
                    results = plates
                    spinning = false
                }
                for a in r["ach"].array {
                    model.showToast("🏆 \(a["t"].string ?? "Достижение") · +\(Fmt.rub(a["r"].double ?? 0))")
                }
            } catch {
                drum?.cancel()
                withAnimation(.snappy) { spinning = false; syncPlaceholder() }
                model.handle(error)
            }
        }
    }

    private func sell(_ keys: [String]) async {
        selling.formUnion(keys)
        defer { selling.subtract(keys) }
        if await model.sell(keys) != nil {
            withAnimation(.snappy) {
                results.removeAll { keys.contains($0.key) }
                if let b = best, keys.contains(b.key) { best = nil; syncPlaceholder() }
                if results.isEmpty { best = nil; syncPlaceholder() }
            }
        }
    }
}
