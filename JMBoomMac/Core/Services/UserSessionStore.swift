import Foundation
import Observation

@MainActor
@Observable
final class UserSessionStore {
    private(set) var user: UserProfile?
    private(set) var endpoint: String?
    private(set) var signInData: SignInDataResult?
    private(set) var isLoggingIn = false
    private(set) var isLoadingSignInData = false
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    var isLoginPresented = false

    private let api: JMBoomAPI
    private let persistence: any UserSessionPersistence
    private var sessionRevision = 0
    @ObservationIgnored private var authenticationExpiredObserver: NSObjectProtocol?

    init(api: JMBoomAPI = .shared, persistence: any UserSessionPersistence = KeychainUserSessionPersistence()) {
        self.api = api
        self.persistence = persistence
        observeAuthenticationExpiration()
        restorePersistedSession()
    }

    var isAuthenticated: Bool {
        user != nil
    }

    var todaySigned: Bool {
        signInData?.todayRecord?.signed ?? false
    }

    func presentLogin() {
        errorMessage = nil
        isLoginPresented = true
    }

    func authenticatedEndpoint(fallback: String) -> String {
        let sessionEndpoint = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return sessionEndpoint.isEmpty ? fallback : sessionEndpoint
    }

    func login(username: String, password: String, endpoint: String) async {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请输入用户名和密码。"
            return
        }

        sessionRevision += 1
        let revision = sessionRevision
        isLoggingIn = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoggingIn = false }

        do {
            let result = try await api.login(username: username, password: password, endpoint: endpoint)
            guard sessionRevision == revision else { return }
            user = result.user
            self.endpoint = result.endpoint
            isLoginPresented = false
            statusMessage = "登录成功"
            await savePersistedSession(username: username, password: password, endpoint: result.endpoint, user: result.user)
            await refreshSignInData(endpoint: result.endpoint)
            await signInIfNeeded(endpoint: result.endpoint)
        } catch {
            guard sessionRevision == revision else { return }
            errorMessage = formattedLoginError(error)
        }
    }

    func logout() async {
        sessionRevision += 1
        let persistenceError: Error?
        do {
            try persistence.delete()
            persistenceError = nil
        } catch {
            persistenceError = error
        }

        await api.clearSession()
        user = nil
        endpoint = nil
        signInData = nil
        statusMessage = "已退出登录"
        errorMessage = persistenceError.map { "本地登录状态清理失败：\($0.localizedDescription)" }
    }

    func refreshSignInData(endpoint: String) async {
        guard let user else { return }
        let endpoint = authenticatedEndpoint(fallback: endpoint)
        isLoadingSignInData = true
        errorMessage = nil
        defer { isLoadingSignInData = false }

        do {
            try await loadSignInData(user: user, endpoint: endpoint)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInIfNeeded(endpoint: String) async {
        guard user != nil else { return }
        let endpoint = authenticatedEndpoint(fallback: endpoint)
        if signInData == nil {
            await refreshSignInData(endpoint: endpoint)
        }
        guard signInData?.todayRecord?.signed == false else { return }
        await signIn(endpoint: endpoint)
    }

    func signIn(endpoint: String) async {
        guard let user else { return }
        let endpoint = authenticatedEndpoint(fallback: endpoint)
        if signInData == nil {
            await refreshSignInData(endpoint: endpoint)
        }
        guard let dailyId = signInData?.dailyId, dailyId > 0 else {
            errorMessage = "签到信息暂不可用。"
            return
        }

        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let result = try await api.signIn(userId: user.id, dailyId: dailyId, endpoint: endpoint)
            statusMessage = result.message.isEmpty ? "签到成功" : result.message
            await refreshSignInData(endpoint: result.endpoint)
            await updatePersistedCookies(endpoint: result.endpoint)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func persistCurrentCookies(endpoint: String) async {
        await updatePersistedCookies(endpoint: authenticatedEndpoint(fallback: endpoint))
    }

    private func observeAuthenticationExpiration() {
        authenticationExpiredObserver = NotificationCenter.default.addObserver(
            forName: .jmAuthenticationExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.expireAuthentication()
            }
        }
    }

    private func expireAuthentication() async {
        guard user != nil else { return }
        sessionRevision += 1
        try? persistence.delete()
        await api.clearSession()
        user = nil
        endpoint = nil
        signInData = nil
        statusMessage = nil
        errorMessage = "登录状态已过期，请重新登录。"
        isLoginPresented = true
    }

    private func restorePersistedSession() {
        do {
            guard let session = try persistence.load() else { return }
            sessionRevision += 1
            let revision = sessionRevision
            user = session.user
            endpoint = session.endpoint
            statusMessage = "已恢复登录状态"
            errorMessage = nil

            Task {
                await restoreNetworkSession(from: session, revision: revision)
            }
        } catch {
            try? persistence.delete()
            errorMessage = "读取登录状态失败：\(error.localizedDescription)"
        }
    }

    private func restoreNetworkSession(from session: PersistedUserSession, revision: Int) async {
        guard isCurrentSession(session, revision: revision) else { return }

        do {
            try await api.restoreSessionCookies(session.cookies, endpoint: session.endpoint)
            guard isCurrentSession(session, revision: revision), let user else { return }
            try await loadSignInData(user: user, endpoint: session.endpoint)
            await signInIfNeeded(endpoint: session.endpoint)
        } catch {
            await renewPersistedSession(from: session, revision: revision)
        }
    }

    private func renewPersistedSession(from session: PersistedUserSession, revision: Int) async {
        guard isCurrentSession(session, revision: revision) else { return }
        guard !session.username.isEmpty, !session.password.isEmpty else {
            statusMessage = "已恢复本地登录状态"
            errorMessage = nil
            return
        }

        do {
            let result = try await api.login(username: session.username, password: session.password, endpoint: session.endpoint)
            guard isCurrentSession(session, revision: revision) else { return }
            user = result.user
            endpoint = result.endpoint
            signInData = nil
            statusMessage = "已恢复登录状态"
            errorMessage = nil
            await savePersistedSession(username: session.username, password: session.password, endpoint: result.endpoint, user: result.user)
            await refreshSignInData(endpoint: result.endpoint)
            await signInIfNeeded(endpoint: result.endpoint)
        } catch {
            guard isCurrentSession(session, revision: revision) else { return }
            user = nil
            endpoint = nil
            signInData = nil
            statusMessage = nil
            errorMessage = "登录状态已过期，请重新登录。"
        }
    }

    private func loadSignInData(user: UserProfile, endpoint: String) async throws {
        isLoadingSignInData = true
        defer { isLoadingSignInData = false }
        signInData = try await api.getSignInData(userId: user.id, endpoint: endpoint)
    }

    @discardableResult
    private func savePersistedSession(username: String, password: String, endpoint: String, user: UserProfile) async -> Bool {
        let cookies = (try? await api.exportSessionCookies(endpoint: endpoint)) ?? []
        let session = PersistedUserSession(
            user: user,
            endpoint: endpoint,
            username: username,
            password: password,
            cookies: cookies,
            savedAt: .now
        )

        do {
            try persistence.save(session)
            return true
        } catch {
            statusMessage = "登录成功，但保存登录状态失败：\(error.localizedDescription)"
            return false
        }
    }

    private func updatePersistedCookies(endpoint: String) async {
        guard let user else { return }
        guard var session = try? persistence.load(), session.user.id == user.id else { return }
        let cookies = (try? await api.exportSessionCookies(endpoint: endpoint)) ?? session.cookies
        session = PersistedUserSession(
            user: user,
            endpoint: endpoint,
            username: session.username,
            password: session.password,
            cookies: cookies,
            savedAt: .now
        )
        try? persistence.save(session)
    }

    private func isCurrentSession(_ session: PersistedUserSession, revision: Int) -> Bool {
        sessionRevision == revision && user?.id == session.user.id && endpoint == session.endpoint
    }

    private func formattedLoginError(_ error: Error) -> String {
        let message = error.localizedDescription
            .replacingOccurrences(of: #"^https?:\/\/[^:\s]+\/login:\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if message.range(of: #"401|unauthorized|用户名|用戶名|password|credential"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "用户名或密码错误。"
        }

        return message.isEmpty ? "登录失败，请稍后重试。" : message
    }
}
