import Foundation

struct APIError: LocalizedError {
    let message: String
    let status: Int
    var errorDescription: String? { message }
}

extension Notification.Name {
    static let gosUnauthorized = Notification.Name("gosUnauthorized")
}

/// Клиент сервера игры: тот же worker.js и те же /api/*, что у Mini App.
/// Вместо данных Telegram (initData) отправляем токен приложения в заголовке Authorization.
enum API {
    static var token: String? {
        get { Keychain.get("token") }
        set { Keychain.set("token", newValue) }
    }

    static func url(_ path: String, query: [String: String] = [:]) -> URL {
        var c = URLComponents(url: AppSettings.serverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return c.url!
    }

    static func get(_ path: String, _ query: [String: String] = [:]) async throws -> J {
        try await send(path, method: "GET", query: query, body: nil, idem: false)
    }

    /// idem: true — добавить ключ x-idem, чтобы повтор запроса (плохая связь) не списал деньги второй раз
    static func post(_ path: String, _ body: [String: Any] = [:], idem: Bool = false) async throws -> J {
        try await send(path, method: "POST", query: [:], body: body, idem: idem)
    }

    private static func send(_ path: String, method: String, query: [String: String], body: [String: Any]?, idem: Bool) async throws -> J {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue(AppSettings.deviceLabel, forHTTPHeaderField: "X-Device")
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let key = UUID().uuidString
        if idem { req.setValue(key, forHTTPHeaderField: "X-Idem") }

        var attempt = 0
        while true {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let j = (try? JSONDecoder().decode(J.self, from: data)) ?? .null
                if status >= 400 || status == 0 {
                    if status == 401, path.hasPrefix("/api/") {
                        await MainActor.run { NotificationCenter.default.post(name: .gosUnauthorized, object: nil) }
                    }
                    throw APIError(message: j["error"].string ?? "Ошибка сервера (\(status))", status: status)
                }
                return j
            } catch let e as APIError {
                throw e
            } catch {
                // обрыв связи: повторяем один раз. С ключом x-idem сервер не выполнит операцию дважды.
                attempt += 1
                if attempt <= 1 && (method == "GET" || idem) {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    continue
                }
                throw APIError(message: "Нет связи с сервером. Проверьте интернет или включите VPN.", status: 0)
            }
        }
    }

    static func media(_ s: String?) -> URL? {
        guard let s, !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: s, relativeTo: AppSettings.serverURL)?.absoluteURL
    }
}
