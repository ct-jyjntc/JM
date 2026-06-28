import SwiftUI

struct LoginView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UserSessionStore.self) private var userSession
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("账号登录")
                    .font(.title2)
                    .bold()
                Text("登录后可同步云端收藏、查看个人资料并自动签到。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("用户名", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.next)

                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
            }

            if let error = userSession.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("取消") {
                    userSession.isLoginPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(userSession.isLoggingIn ? "登录中" : "登录", systemImage: userSession.isLoggingIn ? "arrow.clockwise" : "person.crop.circle", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(userSession.isLoggingIn || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func submit() {
        Task {
            await userSession.login(username: username, password: password, endpoint: settings.apiEndpoint)
        }
    }
}
