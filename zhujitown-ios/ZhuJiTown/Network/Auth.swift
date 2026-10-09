import Foundation

// MARK: - 会话

enum AuthBackend: String, Codable {
    case plugin = "plugin"          // ZhuJiTown Auth 插件（站点账号登录/注册）
    case jwt = "jwt"                // 兼容 JWT Authentication for WP REST API
    case appPassword = "apppass"    // WordPress 自带的 Application Passwords（Basic Auth）

    var label: String {
        switch self {
        case .plugin: return "站点账号"
        case .jwt: return "JWT"
        case .appPassword: return "应用密码"
        }
    }
}

struct Session: Codable, Equatable {
    var token: String = ""
    var userID: Int = 0
    var username: String = ""
    var displayName: String = ""
    var email: String = ""
    var avatarURL: String = ""
    var roles: String = ""
    var canManage: Bool = false
    var backend: AuthBackend = .plugin
    var expireAt: Double = 0
    var basicUser: String = ""
    var basicPass: String = ""

    var name: String { displayName.isEmpty ? username : displayName }
    var isExpired: Bool { expireAt > 0 && Date().timeIntervalSince1970 > expireAt }

    /// 给 /wp-json/wp/v2 请求用的 Authorization 头值
    var authorizationValue: String? {
        switch backend {
        case .plugin, .jwt:
            return token.isEmpty ? nil : "Bearer \(token)"
        case .appPassword:
            guard !basicUser.isEmpty, !basicPass.isEmpty else { return nil }
            let raw = "\(basicUser):\(basicPass)"
            return "Basic \(Data(raw.utf8).base64EncodedString())"
        }
    }
}

enum AuthError: LocalizedError {
    case unavailable(String)
    case server(String)
    case noToken

    var errorDescription: String? {
        switch self {
        case .unavailable(let s): return s
        case .server(let s): return s
        case .noToken: return "服务器未返回令牌"
        }
    }
}

// MARK: - 接口模型

private struct PingPayload: Decodable {
    let ok: Bool?
    let plugin: String?
    let version: String?
    let ttl: Double?
    let registration_open: Bool?
}

private struct AuthUserPayload: Decodable {
    let id: Int?
    let username: String?
    let display_name: String?
    let email: String?
    let roles: [String]?
    let can_manage: Bool?
    let avatar: [String: String]?
}

private struct AuthTokenPayload: Decodable {
    let token: String?
    let expire_at: String?
    let user: AuthUserPayload?
}

private struct ApiErrorPayload: Decodable {
    let code: String?
    let message: String?
}

/// WordPress 原生 `/wp/v2/users/me`（应用密码模式）
private struct WpUserPayload: Decodable {
    let id: Int?
    let username: String?
    let name: String?
    let email: String?
    let roles: [String]?
    let capabilities: [String: Bool]?
    let avatar_urls: [String: String]?
}

private struct JwtPayload: Decodable {
    let token: String?
    let user_email: String?
    let user_nicename: String?
    let user_display_name: String?
}

// MARK: - 客户端

/// 账号认证客户端。三条路径自动降级：
/// 1. ZhuJiTown Auth 插件（可登录 + 可注册）
/// 2. JWT Authentication 插件（可登录）
/// 3. WordPress 自带 Application Passwords（可登录，需用户自行生成）
final class AuthClient {

    static let shared = AuthClient()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 45
        cfg.waitsForConnectivity = true
        cfg.httpAdditionalHeaders = [
            "User-Agent": AppConfig.userAgent,
            "Accept": "application/json"
        ]
        return URLSession(configuration: cfg)
    }()

    private let decoder = JSONDecoder()

    private func root() throws -> URL {
        var s = Prefs.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { throw WPError.badURL("站点地址为空") }
        s += "/wp-json/"
        guard let u = URL(string: s) else { throw WPError.badURL(s) }
        return u
    }

    private func request(_ path: String) throws -> URL {
        try root().appendingPathComponent(path)
    }

    private func basic(_ user: String, _ pass: String) -> String {
        let raw = "\(user):\(pass.replacingOccurrences(of: " ", with: ""))"
        return "Basic \(Data(raw.utf8).base64EncodedString())"
    }

    // MARK: 探测

    /// 站点是否装了 ZhuJiTown Auth 插件
    func pluginAvailable() async -> Bool {
        guard let url = try? request("zhujitown/v1/ping") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              http.statusCode == 200,
              let p = try? decoder.decode(PingPayload.self, from: data) else { return false }
        return p.ok == true || p.plugin == "zhujitown-auth"
    }

    func registrationOpen() async -> Bool {
        guard let url = try? request("zhujitown/v1/ping") else { return false }
        guard let (data, resp) = try? await session.data(for: URLRequest(url: url)),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let p = try? decoder.decode(PingPayload.self, from: data) else { return false }
        return p.registration_open ?? false
    }

    private func jwtAvailable() async -> Bool {
        guard let url = try? request("jwt-auth/v1/token") else { return false }
        guard let (_, resp) = try? await session.data(for: URLRequest(url: url)),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode != 404
    }

    // MARK: 登录 / 注册

    func login(username: String, password: String) async throws -> Session {
        if await pluginAvailable() {
            return try await pluginLogin(username: username, password: password)
        } else if await jwtAvailable() {
            return try await jwtLogin(username: username, password: password)
        }
        return try await appPasswordLogin(username: username, appPassword: password)
    }

    func register(username: String, email: String, password: String) async throws -> Session {
        guard await pluginAvailable() else {
            throw AuthError.unavailable("站点尚未启用 ZhuJiTown Auth 插件，暂不支持在 App 内注册")
        }
        let url = try request("zhujitown/v1/register")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form([
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "device_id": AppConfig.deviceID
        ])
        let payload = try await sendAuth(req)
        guard let t = payload.token, !t.isEmpty else { throw AuthError.noToken }
        return makeSession(payload: payload, fallbackUser: username, backend: .plugin)
    }

    func lostPassword(login: String) async throws {
        guard await pluginAvailable() else {
            throw AuthError.unavailable("站点尚未启用 ZhuJiTown Auth 插件，无法在线找回密码")
        }
        let url = try request("zhujitown/v1/lost-password")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form([
            "user_login": login.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        try await sendRaw(req)
    }

    /// 校验本地会话是否仍有效，返回刷新后的 Session；失效返回 nil
    func validate(_ s: Session) async -> Session? {
        switch s.backend {
        case .plugin:
            guard !s.isExpired, !s.token.isEmpty else { return nil }
            let url = try? request("zhujitown/v1/me")
            guard let url else { return nil }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(s.token)", forHTTPHeaderField: "Authorization")
            guard let (data, resp) = try? await session.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let u = try? decoder.decode(AuthUserPayload.self, from: data) else { return nil }
            var copy = s
            copy.userID = u.id ?? s.userID
            copy.username = u.username ?? s.username
            copy.displayName = u.display_name ?? s.displayName
            copy.email = u.email ?? s.email
            copy.avatarURL = u.avatar?["96"] ?? s.avatarURL
            copy.roles = u.roles?.joined(separator: ",") ?? s.roles
            copy.canManage = u.can_manage ?? false
            return copy

        case .appPassword:
            let url = try? usersMeURL()
            guard let url else { return nil }
            var req = URLRequest(url: url)
            req.setValue(basic(s.basicUser, s.basicPass), forHTTPHeaderField: "Authorization")
            guard let (data, resp) = try? await session.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let u = try? decoder.decode(WpUserPayload.self, from: data) else { return nil }
            var copy = s
            copy.userID = u.id ?? s.userID
            copy.username = u.username ?? s.username
            copy.displayName = u.name ?? s.displayName
            copy.email = u.email ?? s.email
            copy.avatarURL = u.avatar_urls?["96"] ?? s.avatarURL
            copy.roles = u.roles?.joined(separator: ",") ?? s.roles
            copy.canManage = u.capabilities?["edit_posts"] == true
                || u.roles?.contains("administrator") == true
            return copy

        case .jwt:
            return s.isExpired ? nil : s
        }
    }

    func logout(_ s: Session) async {
        guard s.backend == .plugin, !s.token.isEmpty else { return }
        guard let url = try? request("zhujitown/v1/logout") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(s.token)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: req)
    }

    // MARK: 私有实现

    private func pluginLogin(username: String, password: String) async throws -> Session {
        let url = try request("zhujitown/v1/login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form([
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "device_id": AppConfig.deviceID
        ])
        let payload = try await sendAuth(req)
        guard let t = payload.token, !t.isEmpty else { throw AuthError.noToken }
        return makeSession(payload: payload, fallbackUser: username, backend: .plugin)
    }

    private func jwtLogin(username: String, password: String) async throws -> Session {
        let url = try request("jwt-auth/v1/token")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form(["username": username, "password": password])
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(data: data, response: resp)
        guard let p = try? decoder.decode(JwtPayload.self, from: data), let t = p.token, !t.isEmpty else {
            throw AuthError.noToken
        }
        return Session(
            token: t,
            username: p.user_nicename ?? username,
            displayName: p.user_display_name ?? username,
            email: p.user_email ?? "",
            backend: .jwt
        )
    }

    /// `context=edit` 才能拿到 roles / capabilities（决定能否看草稿）
    private func usersMeURL(baseSite: Bool = true) throws -> URL {
        let url = try request("wp/v2/users/me")
        var comp = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comp?.queryItems = [URLQueryItem(name: "context", value: "edit")]
        guard let final = comp?.url else { throw WPError.badURL("users/me") }
        return final
    }

    private func appPasswordLogin(username: String, appPassword: String) async throws -> Session {
        let url = try usersMeURL()
        var req = URLRequest(url: url)
        req.setValue(basic(username, appPassword), forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw WPError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.server("应用密码校验失败（\(http.statusCode)）")
        }
        guard let u = try? decoder.decode(WpUserPayload.self, from: data) else {
            throw WPError.empty
        }
        return Session(
            token: "",
            userID: u.id ?? 0,
            username: u.username ?? username,
            displayName: u.name ?? username,
            email: u.email ?? "",
            avatarURL: u.avatar_urls?["96"] ?? "",
            roles: u.roles?.joined(separator: ",") ?? "",
            canManage: u.capabilities?["edit_posts"] == true
                || u.roles?.contains("administrator") == true,
            backend: .appPassword,
            basicUser: username.trimmingCharacters(in: .whitespacesAndNewlines),
            basicPass: appPassword.replacingOccurrences(of: " ", with: "")
        )
    }

    private func sendAuth(_ req: URLRequest) async throws -> AuthTokenPayload {
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(data: data, response: resp)
        guard let p = try? decoder.decode(AuthTokenPayload.self, from: data) else {
            throw WPError.empty
        }
        return p
    }

    private func sendRaw(_ req: URLRequest) async throws {
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(data: data, response: resp)
    }

    private func checkHTTP(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let e = try? decoder.decode(ApiErrorPayload.self, from: data),
               let msg = e.message, !msg.isEmpty {
                throw AuthError.server(msg)
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            let short = raw.count > 160 ? String(raw.prefix(160)) : raw
            throw WPError.http(code, short)
        }
    }

    private func form(_ dict: [String: String]) -> Data {
        var comps = URLComponents()
        comps.queryItems = dict.map { URLQueryItem(name: $0.key, value: $0.value) }
        return (comps.percentEncodedQuery ?? "").data(using: .utf8) ?? Data()
    }

    private func makeSession(
        payload: AuthTokenPayload,
        fallbackUser: String,
        backend: AuthBackend
    ) -> Session {
        let u = payload.user
        return Session(
            token: payload.token ?? "",
            userID: u?.id ?? 0,
            username: u?.username ?? fallbackUser,
            displayName: u?.display_name ?? fallbackUser,
            email: u?.email ?? "",
            avatarURL: u?.avatar?["96"] ?? "",
            roles: u?.roles?.joined(separator: ",") ?? "",
            canManage: u?.can_manage ?? false,
            backend: backend,
            expireAt: Self.parseExpire(payload.expire_at)
        )
    }

    private static func parseExpire(_ iso: String?) -> Double {
        guard let iso, !iso.isEmpty else { return 0 }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d.timeIntervalSince1970 }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d.timeIntervalSince1970 }
        return 0
    }
}
