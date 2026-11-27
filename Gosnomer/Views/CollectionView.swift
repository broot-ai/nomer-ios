import SwiftUI

struct CollectionView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var rarity: Int? = nil
    @State private var sort: Sort = .value
    @State private var open: Plate?
    @State private var confirmCommons = false

    enum Sort: String, CaseIterable { case value = "По оценке", rarity = "По редкости", fresh = "Сначала новые" }

    private var cfg: GameConfig? { model.config }
    private var sellK: Double { model.me?.j["sellK"].double ?? 1 }

    private var filtered: [Plate] {
        var a = model.plates
        if let rarity { a = a.filter { $0.rarity == rarity } }
        let q = search.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: " ", with: "")
        if !q.isEmpty { a = a.filter { $0.text.uppercased().replacingOccurrences(of: " ", with: "").contains(q) } }
        switch sort {
        case .value: a.sort { $0.value > $1.value }
        case .rarity: a.sort { ($0.rarity, $0.value) > ($1.rarity, $1.value) }
        case .fresh: a.sort { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        }
        return a
    }

    /// обычные номера, которые можно продать прямо сейчас (не на рынке, не на машине, не в избранном)
    private var sellableCommons: [Plate] { model.plates.filter { $0.rarity == 0 && $0.busyReason == nil && !$0.fav } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    rarityFilter
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                Section {
                    if !model.platesLoaded && model.plates.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                    } else if filtered.isEmpty {
                        ContentUnavailableView(model.plates.isEmpty ? "Пока нет номеров" : "Ничего не найдено",
                                               systemImage: "rectangle.stack",
                                               description: Text(model.plates.isEmpty ? "Крутите барабан — выпавшие номера появятся здесь." : "Попробуйте другой фильтр или запрос."))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(filtered) { p in
                        Button { open = p } label: { PlateRow(plate: p, cfg: cfg) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                if p.busyReason == nil {
                                    Button { Task { await model.sell([p.key]) } } label: { Label("Продать", systemImage: "rublesign") }
                                        .tint(.green)
                                }
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Поиск по номеру")
            .refreshable { await model.loadCollection(); await model.refresh() }
            .navigationTitle("Коллекция")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Сортировка", selection: $sort) {
                            ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        if sellableCommons.count > 0 {
                            Divider()
                            Button(role: .destructive) { confirmCommons = true } label: {
                                Label("Продать все обычные (\(sellableCommons.count))", systemImage: "rublesign.circle")
                            }
                        }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            .confirmationDialog("Продать \(sellableCommons.count) обычных номеров?", isPresented: $confirmCommons, titleVisibility: .visible) {
                Button("Продать за \(Fmt.rub((sellableCommons.reduce(0) { $0 + $1.value } * sellK).rounded()))", role: .destructive) {
                    Task { await model.sell(sellableCommons.map(\.key)) }
                }
            } message: {
                Text("Номера на рынке, на машинах и в избранном не трогаем. Отменить продажу нельзя.")
            }
            .sheet(item: $open) { p in PlateDetail(plate: p).presentationDetents([.medium, .large]) }
        }
        .task { if !model.platesLoaded { await model.loadCollection() } }
        .onChange(of: model.tab) { _, t in if (t == .collection || t == .plates) && !model.platesLoaded { Task { await model.loadCollection() } } }
    }

    private var summary: some View {
        let total = model.plates.reduce(0) { $0 + $1.value }
        return HStack(spacing: 12) {
            stat("Номеров", "\(model.plates.count)")
            stat("Оценка", Fmt.short(total) + " ₽")
            stat("Гараж", model.me.map { "\($0.garageUsed)/\($0.garageCap)" } ?? "—")
        }
    }

    private func stat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var rarityFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, "Все", .accentColor)
                ForEach(0..<6, id: \.self) { r in
                    let n = model.plates.filter { $0.rarity == r }.count
                    if n > 0 { chip(r, "\(cfg?.rarityName(r) ?? "") \(n)", Rarity.color(r)) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
    }

    private func chip(_ r: Int?, _ title: String, _ c: Color) -> some View {
        let sel = rarity == r
        return Button {
            Haptic.tap(); withAnimation(.snappy) { rarity = r }
        } label: {
            Text(title).font(.subheadline.weight(sel ? .bold : .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(sel ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .glassEffect(sel ? .regular.tint(c).interactive() : .regular.interactive(), in: .capsule)
    }
}

struct PlateRow: View {
    let plate: Plate
    let cfg: GameConfig?
    var body: some View {
        HStack(spacing: 12) {
            PlateView(kind: plate.kind, parts: plate.parts)
                .frame(width: plate.kind == "moto" || plate.kind == "tractor" ? 60 : 140)
                .frame(width: 140)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(Rarity.color(plate.rarity)).frame(width: 8, height: 8)
                    Text(cfg?.rarityName(plate.rarity) ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(Rarity.color(plate.rarity))
                    if plate.fav { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                }
                Text(Fmt.rub(plate.value)).font(.subheadline.monospacedDigit())
                if let b = plate.busyReason {
                    Text(b).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

/// Карточка номера: как сложилась оценка, состояние, продажа
struct PlateDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let plate: Plate
    @State private var steps: [ValueStep] = []
    @State private var confirm = false
    @State private var busy = false

    var body: some View {
        let p = plate
        let sellK = model.me?.j["sellK"].double ?? 1
        let cfg = model.config
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    PlateView(kind: p.kind, parts: p.parts, glow: p.rarity > 0 ? Rarity.color(p.rarity) : nil)
                        .frame(maxWidth: p.kind == "moto" || p.kind == "tractor" ? 200 : CGFloat.infinity)
                        .padding(.top, 8)
                    HStack(spacing: 8) {
                        Text(cfg?.rarityName(p.rarity) ?? "").font(.title3.bold()).foregroundStyle(Rarity.color(p.rarity))
                        Text("·").foregroundStyle(.secondary)
                        Text(Fmt.rub(p.value)).font(.title3.bold().monospacedDigit())
                    }
                    if let k = cfg?.kind(p.kind) {
                        Text("\(cfg?.flag(k.country) ?? "") \(k.name) · \(k.fmt)").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if !p.tags.isEmpty {
                        FlowTags(tags: p.tags)
                    }
                    if !steps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Как сложилась оценка").font(.headline)
                            ForEach(0..<steps.count, id: \.self) { i in
                                let s = steps[i]
                                HStack {
                                    Text(s.label).font(.subheadline)
                                    Spacer()
                                    if let op = s.op, let d = s.d {
                                        Text("\(op)\(op == "×" ? String(format: "%.2f", d).replacingOccurrences(of: ".", with: ",") : Fmt.num(d))")
                                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Text(Fmt.rub(s.v)).font(.subheadline.weight(.semibold).monospacedDigit())
                                }
                            }
                        }
                        .padding(16)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    }
                    if let b = p.busyReason {
                        Label(b + " — продать сейчас нельзя", systemImage: "lock.fill")
                            .font(.subheadline).foregroundStyle(.orange)
                    } else {
                        Button(role: .destructive) { confirm = true } label: {
                            HStack {
                                if busy { ProgressView() }
                                Text("Продать за \(Fmt.rub((p.value * sellK).rounded()))") }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass).controlSize(.large)
                        .disabled(busy)
                    }
                    Button {
                        model.openTelegram()
                    } label: {
                        Label("Выставить на рынок или аукцион — в Telegram", systemImage: "paperplane").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass).controlSize(.large)
                }
                .padding(20)
            }
            .navigationTitle(p.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .confirmationDialog("Продать \(p.text)?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Продать", role: .destructive) {
                    Task { busy = true; if await model.sell([p.key]) != nil { dismiss() }; busy = false }
                }
            } message: { Text("Номер уйдёт системе. Отменить нельзя.") }
        }
        .task {
            // подробная оценка (шаги) приходит в /api/plate
            if let r = try? await API.get("/api/plate", ["key": plate.key]), !r["plate"].isNull {
                steps = Plate(r["plate"]).steps
            }
        }
    }
}

struct FlowTags: View {
    let tags: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { t in
                    Text(t).font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                }
            }
        }
    }
}
