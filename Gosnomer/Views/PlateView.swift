import SwiftUI

/// Номерной знак любого вида игры. Пропорции по стандартам (РФ 520×112 мм, мото 190×145, трактор 290×170).
struct PlateView: View {
    let kind: String
    let parts: [String: String]
    var glow: Color? = nil

    var body: some View {
        let st = PlateStyle.of(kind)
        GeometryReader { g in
            let h = g.size.height
            ZStack {
                RoundedRectangle(cornerRadius: h * (st.square ? 0.07 : 0.11), style: .continuous)
                    .fill(st.bg)
                RoundedRectangle(cornerRadius: h * (st.square ? 0.055 : 0.085), style: .continuous)
                    .strokeBorder(st.fg, lineWidth: max(1, h * (st.square ? 0.018 : 0.03)))
                    .padding(h * (st.square ? 0.025 : 0.045))
                content(st, h: h)
                    .padding(h * (st.square ? 0.05 : 0.075))
            }
        }
        .aspectRatio(st.ratio, contentMode: .fit)
        .shadow(color: (glow ?? .clear).opacity(glow == nil ? 0 : 0.75), radius: glow == nil ? 0 : 14)
        .accessibilityElement()
        .accessibilityLabel(Text(PlateView.text(kind, parts)))
    }

    private func p(_ k: String) -> String { parts[k] ?? "" }

    @ViewBuilder
    private func content(_ st: PlateStyle, h: CGFloat) -> some View {
        switch kind {
        case "moto", "tractor":
            VStack(spacing: h * 0.02) {
                PT(p("d"), h * 0.44, st.fg)
                HStack(alignment: .center, spacing: h * 0.05) {
                    PT(p("l"), h * 0.34, st.fg)
                    VStack(spacing: 0) {
                        PT(p("r"), h * 0.26, st.fg)
                        HStack(spacing: h * 0.02) {
                            Text("RUS").font(.system(size: h * 0.085, weight: .bold)).foregroundStyle(st.fg)
                            MiniFlag(country: "ru").frame(width: h * 0.11, height: h * 0.065)
                        }
                    }
                }
            }
        case "dubai":
            HStack(spacing: h * 0.1) {
                VStack(spacing: 0) {
                    Text("DUBAI").font(.system(size: h * 0.17, weight: .heavy)).foregroundStyle(st.fg)
                    Text("دبي").font(.system(size: h * 0.17, weight: .bold)).foregroundStyle(st.fg)
                }
                PT(p("c"), h * 0.6, st.fg)
                Spacer(minLength: 0)
                PT(p("n"), h * 0.72, st.fg)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, h * 0.08)
        case "abu":
            HStack(spacing: h * 0.1) {
                PT(p("c"), h * 0.5, .white)
                    .frame(width: h * 0.95, height: h * 0.72)
                    .background(Color(red: 0.78, green: 0.06, blue: 0.18), in: .rect(cornerRadius: h * 0.08))
                VStack(spacing: 0) {
                    Text("ABU DHABI").font(.system(size: h * 0.13, weight: .heavy)).foregroundStyle(st.fg)
                    Text("أبوظبي").font(.system(size: h * 0.15, weight: .bold)).foregroundStyle(st.fg)
                }
                .fixedSize()
                Spacer(minLength: 0)
                PT(p("n"), h * 0.72, st.fg)
                Spacer(minLength: 0)
            }
        case "uk":
            HStack(spacing: h * 0.12) {
                VStack(spacing: 2) {
                    Text("UK").font(.system(size: h * 0.2, weight: .heavy)).foregroundStyle(.white)
                }
                .frame(width: h * 0.5).frame(maxHeight: .infinity)
                .background(Color(red: 0.0, green: 0.2, blue: 0.6), in: .rect(cornerRadius: h * 0.06))
                Spacer(minLength: 0)
                PT(p("a") + p("d") + " " + p("z"), h * 0.72, st.fg)
                Spacer(minLength: 0)
            }
        case "by":
            HStack(spacing: h * 0.1) {
                VStack(spacing: h * 0.03) {
                    MiniFlag(country: "by").frame(width: h * 0.42, height: h * 0.26)
                    Text("BY").font(.system(size: h * 0.17, weight: .heavy)).foregroundStyle(st.fg)
                }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: h * 0.1) {
                    PT(p("d"), h * 0.72, st.fg)
                    PT(p("l") + "-" + p("r"), h * 0.6, st.fg)
                }
                Spacer(minLength: 0)
            }
        default:
            long(st, h: h)
        }
    }

    /// «длинные» номера РФ и Казахстана: основное поле + поле региона
    private func long(_ st: PlateStyle, h: CGFloat) -> some View {
        let main: [(String, CGFloat)] = {
            switch kind {
            case "civil":
                let l = Array(p("l"))
                return [(l.first.map(String.init) ?? "", 0.58), (p("d"), 0.74), (String(l.dropFirst()), 0.58)]
            case "taxi", "police", "trailer": return [(p("l"), 0.58), (p("d"), 0.74)]
            case "military": return [(p("d"), 0.74), (p("l"), 0.58)]
            case "diplomatic": return [(p("c"), 0.66), (p("l"), 0.66), (p("n"), 0.66)]
            case "kz": return [(p("d"), 0.72), (p("l"), 0.62)]
            default: return [(p("l") + p("d"), 0.7)]
            }
        }()
        let r = p("r")
        let isKZ = kind == "kz"
        let ruFlag = ["civil", "taxi", "trailer"].contains(kind)
        return HStack(spacing: 0) {
            if isKZ {
                VStack(spacing: h * 0.02) {
                    MiniFlag(country: "kz").frame(width: h * 0.36, height: h * 0.22)
                    Text("KZ").font(.system(size: h * 0.16, weight: .heavy)).foregroundStyle(st.fg)
                }
                .frame(width: h * 0.55)
            }
            HStack(alignment: .lastTextBaseline, spacing: h * 0.08) {
                ForEach(0..<main.count, id: \.self) { i in
                    PT(main[i].0, h * main[i].1, st.fg)
                }
            }
            .frame(maxWidth: .infinity)
            if !r.isEmpty {
                Rectangle().fill(st.fg).frame(width: max(1, h * 0.03))
                    .padding(.vertical, -h * 0.03)
                VStack(spacing: -h * 0.02) {
                    PT(r, h * (isKZ ? 0.6 : 0.5), st.fg)
                    if !isKZ {
                        HStack(spacing: h * 0.04) {
                            Text("RUS").font(.system(size: h * 0.16, weight: .bold)).foregroundStyle(st.fg)
                            if ruFlag { MiniFlag(country: "ru").frame(width: h * 0.24, height: h * 0.14) }
                        }
                    }
                }
                .frame(width: h * (r.count > 2 ? 1.22 : 0.98))
            }
        }
    }
}

/// Текст номера: плотный жирный шрифт, цифры одинаковой ширины (барабан не «прыгает»)
private struct PT: View {
    let s: String, size: CGFloat, color: Color
    init(_ s: String, _ size: CGFloat, _ color: Color) { self.s = s; self.size = size; self.color = color }
    var body: some View {
        Text(s)
            .font(.system(size: size, weight: .bold).width(.condensed))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText())
    }
}

struct MiniFlag: View {
    let country: String
    var body: some View {
        Group {
            switch country {
            case "by":
                VStack(spacing: 0) {
                    Color(red: 0.8, green: 0.1, blue: 0.15).frame(maxHeight: .infinity).layoutPriority(2)
                    Color(red: 0.0, green: 0.55, blue: 0.25).frame(maxHeight: .infinity)
                }
            case "kz":
                ZStack {
                    Color(red: 0.0, green: 0.69, blue: 0.79)
                    Circle().fill(Color(red: 1.0, green: 0.8, blue: 0.0)).padding(3)
                }
            default:
                VStack(spacing: 0) {
                    Color.white
                    Color(red: 0.0, green: 0.22, blue: 0.65)
                    Color(red: 0.84, green: 0.17, blue: 0.12)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 1.5))
        .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(.black.opacity(0.25), lineWidth: 0.5))
    }
}

struct PlateStyle {
    let bg: Color
    let fg: Color
    let ratio: CGFloat
    var square = false

    static func of(_ kind: String) -> PlateStyle {
        let white = Color.white, black = Color.black
        let yellow = Color(red: 0.98, green: 0.80, blue: 0.10)
        switch kind {
        case "taxi": return .init(bg: yellow, fg: black, ratio: 520 / 112)
        case "police": return .init(bg: Color(red: 0.10, green: 0.30, blue: 0.72), fg: white, ratio: 520 / 112)
        case "military": return .init(bg: Color(white: 0.08), fg: white, ratio: 520 / 112)
        case "diplomatic": return .init(bg: Color(red: 0.78, green: 0.06, blue: 0.18), fg: white, ratio: 520 / 112)
        case "moto": return .init(bg: white, fg: black, ratio: 190 / 145, square: true)
        case "tractor": return .init(bg: white, fg: black, ratio: 290 / 170, square: true)
        case "uk": return .init(bg: yellow, fg: black, ratio: 520 / 111)
        case "dubai", "abu": return .init(bg: white, fg: black, ratio: 520 / 110)
        default: return .init(bg: white, fg: black, ratio: 520 / 112)
        }
    }
}

// MARK: - барабан

extension PlateView {
    /// бледная заглушка до первой крутки, как в Mini App: «А 000 АА 00»
    static func sample(_ kind: String) -> [String: String] {
        switch kind {
        case "taxi": return ["l": "АА", "d": "000", "r": "00"]
        case "police": return ["l": "А", "d": "0000", "r": "00"]
        case "military": return ["d": "0000", "l": "АА", "r": "00"]
        case "diplomatic": return ["c": "000", "l": "D", "n": "000", "r": "00"]
        case "trailer": return ["l": "АА", "d": "0000", "r": "00"]
        case "moto", "tractor": return ["d": "0000", "l": "АА", "r": "00"]
        case "dubai": return ["c": "A", "n": "00000"]
        case "abu": return ["c": "1", "n": "00000"]
        case "kz": return ["d": "000", "l": "AAA", "r": "00"]
        case "by": return ["d": "0000", "l": "AA", "r": "0"]
        case "uk": return ["a": "AA", "d": "00", "z": "AAA"]
        default: return ["l": "ААА", "d": "000", "r": "00"]
        }
    }

    static func keyOrder(_ kind: String) -> [String] {
        switch kind {
        case "military", "moto", "tractor", "kz", "by": return ["d", "l", "r"]
        case "diplomatic": return ["c", "l", "n", "r"]
        case "dubai", "abu": return ["c", "n"]
        case "uk": return ["a", "d", "z"]
        default: return ["l", "d", "r"]
        }
    }

    /// порядок, в котором символы останавливаются: слева направо, как видит игрок
    static func revealOrder(_ kind: String, _ parts: [String: String]) -> [(String, Int)] {
        var out: [(String, Int)] = []
        if kind == "civil" {
            let l = parts["l"]?.count ?? 0, d = parts["d"]?.count ?? 0, r = parts["r"]?.count ?? 0
            if l > 0 { out.append(("l", 0)) }
            for i in 0..<d { out.append(("d", i)) }
            if l > 1 { for i in 1..<l { out.append(("l", i)) } }
            for i in 0..<r { out.append(("r", i)) }
            return out
        }
        for k in keyOrder(kind) {
            let n = parts[k]?.count ?? 0
            for i in 0..<n { out.append((k, i)) }
        }
        return out
    }

    /// первые `revealed` символов — настоящие, остальные — случайные того же типа
    static func scramble(_ kind: String, _ target: [String: String], revealed: Int) -> [String: String] {
        var out = target.mapValues { Array($0) }
        let order = revealOrder(kind, target)
        for (i, pos) in order.enumerated() where i >= revealed {
            guard var arr = out[pos.0], pos.1 < arr.count else { continue }
            arr[pos.1] = randomLike(arr[pos.1])
            out[pos.0] = arr
        }
        return out.mapValues { String($0) }
    }

    static func random(_ kind: String) -> [String: String] { scramble(kind, sample(kind), revealed: 0) }

    private static let cyr = Array("АВЕКМНОРСТУХ"), lat = Array("ABCDEFHKMNOPRSTXYZ"), dig = Array("0123456789")
    private static func randomLike(_ c: Character) -> Character {
        if c.isNumber { return dig.randomElement()! }
        if c.isASCII && c.isLetter { return lat.randomElement()! }
        if c.isLetter { return cyr.randomElement()! }
        return c
    }

    static func text(_ kind: String, _ parts: [String: String]) -> String {
        keyOrder(kind).compactMap { parts[$0] }.joined(separator: " ")
    }
}
