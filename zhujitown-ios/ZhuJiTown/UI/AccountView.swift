import SwiftUI

/// 账号中心：登录 / 注册 / 找回密码 / 退出。
/// 三条可用路径由 AuthClient 自动选择：ZhuJiTown Auth 插件 → JWT 插件 → WordPress 应用密码。
struct AccountView: View {

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case login, register
        var id: String { rawValue }
        var title: String {
            switch self {
            case .login: return "登录"
            case .register: return "注册"
            }
        }
    }

    @State private var mode: Mode = .login
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var confirm = ""
    @State private var showPassword = false
    @State private var showLost = false
    @State private var lostLogin = ""

    var body: some View {
        NavigationStack {
            Form {
                if app.session != nil {
                    profileSection
                } else {
                    modeSection
                    if mode == .login {
                        loginSection
                    } else {
                        registerSection
                    }
                    backendSection
                }
            }
            .navigationTitle(app.session == nil ? "账号" : "我的账号")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                if !app.registrationOpen { mode = .login }
            }
        }
    }

    // MARK: 已登录

    private var profileSection: some View {
        Section {
            if let s = app.session {
                HStack(spacing: 14) {
                    avatar(for: s)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.name).font(.headline)
                        if !s.email.isEmpty {
                            Text(s.email).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("登录方式：\(s.backend.label)")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .padding(.vertical, 4)

                if s.canManage {
                    Label("已具备草稿查看权限", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                Button(role: .destructive) {
                    Task { await app.logout() }
                } label: {
                    Text("退出登录")
                }
            }
        } header: {
            Text("当前账号")
        }
    }

    @ViewBuilder
    private func avatar(for s: Session) -> some View {
        if let url = URL(string: s.avatarURL), !s.avatarURL.isEmpty {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 54, height: 54)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(AppTheme.accent.opacity(0.18))
                .frame(width: 54, height: 54)
                .overlay(
                    Text(String(s.name.prefix(1)).uppercased())
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                )
        }
    }

    // MARK: 未登录

    private var modeSection: some View {
        Section {
            if app.registrationOpen {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } else {
                Text("当前站点未开放注册，只能登录已有账号。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loginSection: some View {
        Section {
            TextField("用户名或邮箱", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
            HStack {
                if showPassword {
                    TextField("密码", text: $password)
                        .textContentType(.password)
                } else {
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                }
                Button(showPassword ? "隐藏" : "显示") { showPassword.toggle() }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }

            messageRow

            Button {
                Task { await app.login(username: username, password: password) }
            } label: {
                HStack {
                    Spacer()
                    if app.authBusy { ProgressView().controlSize(.small) }
                    Text(app.authBusy ? "登录中…" : "登录").fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(app.authBusy || username.isEmpty || password.isEmpty)

            Button {
                withAnimation { showLost.toggle() }
            } label: {
                Text("忘记密码？").font(.footnote)
            }
            .buttonStyle(.borderless)

            if showLost {
                VStack(alignment: .leading, spacing: 8) {
                    Text("填写用户名或邮箱，站点会给你的邮箱发送重置密码邮件。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("用户名或邮箱", text: $lostLogin)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("发送重置邮件") {
                        Task { await app.lostPassword(lostLogin) }
                    }
                    .disabled(app.authBusy || lostLogin.isEmpty)
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text("登录")
        }
    }

    private var registerSection: some View {
        Section {
            Text("注册的是你站点上的账号，新账号默认角色为订阅者。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("用户名（至少 3 个字符）", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("邮箱", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
            SecureField("密码（至少 6 位）", text: $password)
                .textContentType(.newPassword)
            SecureField("确认密码", text: $confirm)
                .textContentType(.newPassword)

            if !confirm.isEmpty && confirm != password {
                Text("两次输入的密码不一致")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            messageRow

            Button {
                Task { await app.register(username: username, email: email, password: password) }
            } label: {
                HStack {
                    Spacer()
                    if app.authBusy { ProgressView().controlSize(.small) }
                    Text(app.authBusy ? "注册中…" : "注册并登录").fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(app.authBusy || username.isEmpty || email.isEmpty ||
                      password.count < 6 || password != confirm)
        } header: {
            Text("注册")
        }
    }

    private var backendSection: some View {
        Section {
            Text(app.pluginReady
                 ? "已检测到站点启用了 ZhuJiTown Auth 插件，可直接用站点账号登录\(app.registrationOpen ? "、注册" : "")。"
                 : "站点尚未启用 ZhuJiTown Auth 插件，当前使用 WordPress 自带的「应用程序密码」登录：到网站后台 → 用户 → 个人资料里生成一串应用密码，填在上面的用户名 / 密码即可。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("说明")
        }
    }

    @ViewBuilder
    private var messageRow: some View {
        if let err = app.authError {
            Text(err).font(.footnote).foregroundStyle(.red)
        }
        if let note = app.authNotice {
            Text(note).font(.footnote).foregroundStyle(.green)
        }
    }
}

#Preview {
    AccountView().environmentObject(AppModel())
}
