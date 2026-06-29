import Foundation
import WebKit

enum WebCookieBridge {
    @MainActor
    static func copySharedCookies(to store: WKHTTPCookieStore, for urls: [URL]) async {
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let hosts = Set(urls.compactMap(\.host))
        let matchingCookies = cookies.filter { cookie in
            hosts.contains { host in
                cookie.domainMatches(host)
            }
        }

        for cookie in matchingCookies where !cookie.isExpired {
            await store.setCookieAsync(cookie)
        }
    }

    @MainActor
    static func copyWebCookiesToShared(from store: WKHTTPCookieStore) async {
        let cookies = await store.allCookiesAsync()
        for cookie in cookies where !cookie.isExpired {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
}

private extension WKHTTPCookieStore {
    @MainActor
    func allCookiesAsync() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    @MainActor
    func setCookieAsync(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            setCookie(cookie) {
                continuation.resume()
            }
        }
    }
}

private extension HTTPCookie {
    var isExpired: Bool {
        guard let expiresDate else { return false }
        return expiresDate <= Date()
    }

    func domainMatches(_ host: String) -> Bool {
        let normalizedDomain = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let normalizedHost = host.lowercased()
        return normalizedHost == normalizedDomain || normalizedHost.hasSuffix(".\(normalizedDomain)")
    }
}
