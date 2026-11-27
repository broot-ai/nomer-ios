import Foundation

/// Гибкое JSON-значение: сервер игры отдаёт много полей и постоянно растёт,
/// поэтому читаем ответ «как есть» и берём нужные поля, не падая на новых или пустых.
enum J: Decodable, Equatable {
    case null
    case bool(Bool)
    case num(Double)
    case str(String)
    case arr([J])
    case obj([String: J])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .num(d) }
        else if let s = try? c.decode(String.self) { self = .str(s) }
        else if let a = try? c.decode([J].self) { self = .arr(a) }
        else if let o = try? c.decode([String: J].self) { self = .obj(o) }
        else { self = .null }
    }

    subscript(_ k: String) -> J {
        if case .obj(let o) = self { return o[k] ?? .null }
        return .null
    }
    subscript(_ i: Int) -> J {
        if case .arr(let a) = self, i >= 0, i < a.count { return a[i] }
        return .null
    }

    var isNull: Bool { if case .null = self { return true }; return false }
    var string: String? {
        switch self {
        case .str(let s): return s
        case .num(let d): return d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
        default: return nil
        }
    }
    var double: Double? {
        switch self {
        case .num(let d): return d
        case .str(let s): return Double(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
    var int: Int? { double.map { Int($0.rounded()) } }
    var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .num(let d): return d != 0
        case .str(let s): return !s.isEmpty && s != "0"
        default: return false
        }
    }
    var array: [J] { if case .arr(let a) = self { return a }; return [] }
    var object: [String: J] { if case .obj(let o) = self { return o }; return [:] }
}
