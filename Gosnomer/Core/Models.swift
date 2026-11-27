import SwiftUI

extension J {
    /// склейка объектов: новые поля заменяют старые (ответ крутки содержит урезанный профиль)
    func merged(with other: J) -> J {
        guard case .obj(var a) = self, case .obj(let b) = other else { return other.isNull ? self : other }
        for (k, v) in b { a[k] = v }
        return .obj(a)
    }
}

/// Профиль игрока (/api/me → me)
struct Me {
    let j: J
    var id: Int { j["id"].int ?? 0 }
    var name: String { j["name"].string ?? "Игрок" }
    var username: String? { j["username"].string.flatMap { $0.isEmpty ? nil : $0 } }
    var photo: URL? { API.media(j["photo"].string) }
    var balance: Double { j["balance"].double ?? 0 }
    var hideBal: Bool { j["hideBal"].bool }
    var starBal: Int { j["starBal"].int ?? 0 }
    var level: Int { j["level"].int ?? 1 }
    var xp: Double { j["xp"].double ?? 0 }
    var xpFrom: Double { j["xpFrom"].double ?? 0 }
    var xpTo: Double { j["xpTo"].double ?? 1 }
    var spins: Int { j["spins"].int ?? 0 }
    var garageCap: Int { j["garageCap"].int ?? 0 }
    var garageUsed: Int { j["garageUsed"].int ?? 0 }
    var canDaily: Bool { j["canDaily"].bool }
    var streak: Int { j["streak"].int ?? 0 }
    var nextDaily: Date { Date(timeIntervalSince1970: (j["nextDaily"].double ?? 0) / 1000) }
    var needGroup: Bool { j["needGroup"].bool }
    var isAdmin: Bool { j["isAdmin"].bool }
    var vip: Bool { (j["vipUntil"].double ?? 0) / 1000 > Date().timeIntervalSince1970 }
    var wallets: [String: Double] { j["wallets"].object.compactMapValues { $0.double } }
    var stats: J { j["stats"] }
    var levelProgress: Double { xpTo > xpFrom ? min(1, max(0, (xp - xpFrom) / (xpTo - xpFrom))) : 0 }
}

struct KindInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let country: String
    let max: Int
    let fmt: String
}

/// Настройки игры (/api/me → config)
struct GameConfig {
    let j: J
    /// порядок видов — как в списке выбора в Mini App
    static let order = ["civil", "taxi", "police", "military", "diplomatic", "trailer", "moto", "tractor", "dubai", "abu", "kz", "by", "uk"]

    var kinds: [KindInfo] {
        let all = j["kinds"].object
        let keys = Self.order.filter { all[$0] != nil } + all.keys.filter { !Self.order.contains($0) }.sorted()
        return keys.map { k in
            let v = all[k] ?? .null
            return KindInfo(id: k, name: v["name"].string ?? k, country: v["country"].string ?? "ru", max: v["max"].int ?? 5, fmt: v["fmt"].string ?? "")
        }
    }
    func kind(_ id: String) -> KindInfo? { kinds.first { $0.id == id } }
    func flag(_ country: String) -> String { j["countries"][country]["flag"].string ?? "🏳️" }
    func countryName(_ country: String) -> String { j["countries"][country]["name"].string ?? country }
    var tiers: [(id: String, name: String, min: Int)] {
        j["tiers"].array.map { ($0["id"].string ?? "", $0["name"].string ?? "", $0["min"].int ?? 0) }
    }
    func price(_ kind: String, _ tier: Int) -> Double { j["price"][kind][tier].double ?? 0 }
    func odds(_ kind: String, _ tier: Int) -> [Double] { j["odds"][kind][tier].array.compactMap { $0.double } }
    var rarityNames: [String] {
        let a = j["rarity"].array.compactMap { $0.string }
        return a.isEmpty ? ["Обычный", "Необычный", "Редкий", "Эпический", "Легендарный", "Мифический"] : a
    }
    func rarityName(_ r: Int) -> String { rarityNames.indices.contains(r) ? rarityNames[r] : "—" }
    /// валюта вида номера: nil — рубли
    func currency(_ country: String) -> String? { j["fx"]["map"][country].string }
    func fxRate(_ cur: String) -> Double { j["fx"]["rates"][cur].double ?? 1 }
    func fxSymbol(_ cur: String) -> String { j["fx"]["info"][cur]["sym"].string ?? cur }
    var bot: String { j["bot"].string ?? "GosnomerGame" }
    var owner: String { j["owner"].string ?? "@Verifure" }
    var groupLink: String? { j["group"]["link"].string.flatMap { $0.isEmpty ? nil : $0 } }
    var maintenance: Bool { j["maintenance"].bool }
    var demo: Bool { j["demo"].bool }
    var demoText: String { j["demoText"].string ?? "" }
}

struct ValueStep: Hashable {
    let label: String
    let op: String?
    let d: Double?
    let v: Double
}

/// Номерной знак игрока
struct Plate: Identifiable, Hashable {
    let key: String
    let kind: String
    let text: String
    let parts: [String: String]
    let value: Double
    let rarity: Int
    let tags: [String]
    let steps: [ValueStep]
    let listed: Double?
    let auction: Bool
    let onCar: Bool
    let credit: Bool
    let lock: String?
    let fav: Bool
    let created: Date?
    var id: String { key }

    init(_ j: J) {
        key = j["key"].string ?? j["id"].string ?? UUID().uuidString
        kind = j["kind"].string ?? "civil"
        text = j["text"].string ?? ""
        parts = j["parts"].object.compactMapValues { $0.string }
        value = j["value"].double ?? 0
        rarity = j["rarity"].int ?? 0
        tags = j["tags"].array.compactMap { $0.string }
        steps = j["steps"].array.map { ValueStep(label: $0["label"].string ?? "", op: $0["op"].string, d: $0["d"].double, v: $0["v"].double ?? 0) }
        listed = j["listed"].double
        auction = !j["auction"].isNull
        onCar = !j["oncar"].isNull && j["oncar"].bool != false
        credit = !j["credit"].isNull
        lock = j["lock"].string
        fav = j["fav"].bool
        created = j["created"].double.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// почему номер нельзя продать прямо сейчас (сервер всё равно проверит сам)
    var busyReason: String? {
        if listed != nil { return "Выставлен на продажу" }
        if auction { return "На аукционе" }
        if onCar { return "Стоит на машине" }
        if credit { return "В залоге по кредиту" }
        if let lock, !lock.isEmpty { return "Заблокирован (\(lock))" }
        return nil
    }
}

enum Rarity {
    static func color(_ r: Int) -> Color {
        switch r {
        case 1: return Color(red: 0.204, green: 0.780, blue: 0.349)   // #34c759
        case 2: return Color(red: 0.039, green: 0.518, blue: 1.0)     // #0a84ff
        case 3: return Color(red: 0.686, green: 0.322, blue: 0.871)   // #af52de
        case 4: return Color(red: 1.0, green: 0.584, blue: 0.0)       // #ff9500
        case 5: return Color(red: 1.0, green: 0.176, blue: 0.333)     // #ff2d55
        default: return Color(red: 0.557, green: 0.557, blue: 0.576)  // #8e8e93
        }
    }
}

enum Fmt {
    private static let nf: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 2
        return f
    }()
    static func num(_ v: Double) -> String {
        nf.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }
    static func rub(_ v: Double) -> String { num(v) + " ₽" }
    /// 1,2 млн ₽ — для узких мест
    static func short(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1e12 { return trim(v / 1e12) + " трлн" }
        if a >= 1e9 { return trim(v / 1e9) + " млрд" }
        if a >= 1e6 { return trim(v / 1e6) + " млн" }
        if a >= 1e4 { return trim(v / 1e3) + " тыс" }
        return num(v)
    }
    private static func trim(_ v: Double) -> String {
        let s = String(format: v >= 100 ? "%.0f" : "%.1f", v).replacingOccurrences(of: ".", with: ",")
        return s.hasSuffix(",0") ? String(s.dropLast(2)) : s
    }
    static func percent(_ p: Double) -> String {
        let x = p * 100
        if x == 0 { return "0%" }
        if x >= 10 { return String(format: "%.0f%%", x) }
        if x >= 1 { return String(format: "%.1f%%", x).replacingOccurrences(of: ".", with: ",") }
        if x >= 0.01 { return String(format: "%.2f%%", x).replacingOccurrences(of: ".", with: ",") }
        return String(format: "%.3f%%", x).replacingOccurrences(of: ".", with: ",")
    }
}

/// Понятные тексты для кодов ошибок сервера
enum ServerErr {
    static func text(_ e: Error, config: GameConfig?, me: Me?) -> String {
        let m = (e as? APIError)?.message ?? e.localizedDescription
        if m == "garage_full" {
            let cap = me.map { " (\($0.garageUsed) из \($0.garageCap))" } ?? ""
            return "Гараж для номеров заполнен\(cap). Продайте лишние номера в «Коллекции»."
        }
        if m == "demo_mode" { return config?.demoText.isEmpty == false ? config!.demoText : "Игра обновляется — сейчас можно только смотреть." }
        if m == "need_group" { return "Чтобы играть, нужно состоять в группе игры." }
        if m.hasPrefix("need_fx:") {
            let p = m.split(separator: ":")
            let cur = p.count > 1 ? String(p[1]) : ""
            let amt = p.count > 2 ? Double(p[2]) ?? 0 : 0
            let sym = config?.fxSymbol(cur) ?? cur
            return "Не хватает \(Fmt.num(amt)) \(sym). Обменять рубли на валюту можно в игре в Telegram, раздел «Кошелёк»."
        }
        if m.hasPrefix("need_stars") { return "Не хватает звёзд на счёте игры." }
        return m
    }
}
