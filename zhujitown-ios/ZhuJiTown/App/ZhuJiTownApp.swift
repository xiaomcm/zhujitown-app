import SwiftUI

@main
struct ZhuJiTownApp: App {
    @StateObject private var app = AppModel()
    @AppStorage(PrefKey.appearance.rawValue) private var appearanceRaw: String = "auto"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(preferredScheme)
                .accentColor(AppTheme.accent)
                .onAppear {
                    // 列表/单元格的默认蓝色改成站点主色
                    UIView.appearance().tintColor = UIColor(AppTheme.accent)
                    UINavigationBar.appearance().largeTitleTextAttributes = [
                        .foregroundColor: UIColor.label
                    ]
                }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch Prefs.Appearance(rawValue: appearanceRaw) {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }
}
