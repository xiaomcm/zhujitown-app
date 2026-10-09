import Foundation

/// 站点默认配置。
/// App 不再内置任何管理员凭据：账号由用户在 App 内登录（ZhuJiTown Auth 插件或 WordPress 应用密码），
/// 令牌保存在本机 UserDefaults，不进版本库、不随包分发。
enum AppConfig {
    static let siteURL = "https://www.zhujitown.com"

    static let appVersion = "1.0.0"
    static let userAgent = "ZhuJiTowniOS/\(appVersion) (+https://www.zhujitown.com)"

    /// 自定义 URL Scheme：Safari 里打开 `zhujitown://post/3149` 可唤起 App
    static let urlScheme = "zhujitown"

    /// 设备标识（用于令牌签发时区分客户端，非唯一追踪 ID）
    static let deviceID: String = {
        let key = "com.zhujitown.deviceID"
        if let existed = UserDefaults.standard.string(forKey: key) { return existed }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()
}
