import Foundation

struct UserProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UInt32
    let username: String
    let email: String
    let avatar: String
    let avatarURL: String
    let level: UInt32
    let levelName: String
    let currentLevelExp: UInt32
    let nextLevelExp: UInt32
    let expPercent: Double
    let currentCollectCount: UInt32
    let maxCollectCount: UInt32
    let jCoin: UInt32
}

struct LoginResult: Sendable {
    let endpoint: String
    let user: UserProfile
}

struct PersistedUserSession: Codable, Hashable, Sendable {
    let user: UserProfile
    let endpoint: String
    let username: String
    let password: String
    let cookies: [StoredHTTPCookie]
    let savedAt: Date
}

struct StoredHTTPCookie: Codable, Hashable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path.isEmpty ? "/" : cookie.path
        expiresDate = cookie.expiresDate
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
    }

    var isExpired: Bool {
        guard let expiresDate else { return false }
        return expiresDate <= Date()
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path.isEmpty ? "/" : path
        ]

        if let expiresDate {
            properties[.expires] = expiresDate
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        if isHTTPOnly {
            properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
        }

        return HTTPCookie(properties: properties)
    }
}

struct SignInDataResult: Sendable {
    let endpoint: String
    let dailyId: UInt32
    let threeDaysCoin: UInt32
    let threeDaysExp: UInt32
    let sevenDaysCoin: UInt32
    let sevenDaysExp: UInt32
    let eventName: String
    let currentProgress: String
    let backgroundPC: String
    let backgroundPhone: String
    let records: [SignInRecord]

    var todayRecord: SignInRecord? {
        let today = Calendar.current.component(.day, from: .now)
        return records.first { Int($0.day) == today }
    }
}

struct SignInRecord: Identifiable, Hashable, Sendable {
    var id: UInt32 { day }

    let day: UInt32
    let date: String
    let signed: Bool
    let bonus: Bool
}

struct SignInResult: Sendable {
    let endpoint: String
    let message: String
}

struct FavoriteToggleResult: Sendable {
    let endpoint: String
    let favorited: Bool
}

struct PurchaseComicResult: Sendable {
    let endpoint: String
    let message: String
}

struct PurchasedComicItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
    let price: UInt32
    let updatedAt: Date
}

struct FavoriteFolder: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct FavoriteListResult: Sendable {
    let endpoint: String
    let page: Int
    let total: Int
    let hasMore: Bool
    let folders: [FavoriteFolder]
    let items: [FeedComic]
}

struct ComicCommentsResult: Sendable {
    let endpoint: String
    let page: Int
    let total: Int
    let comments: [ComicComment]
}

struct CommentActionResult: Sendable {
    let endpoint: String
    let message: String
}

struct ComicComment: Identifiable, Hashable, Sendable {
    let id: String
    let comicId: String?
    let userId: String
    let username: String
    let nickname: String
    let content: String
    let likeCount: UInt32
    let time: String
    let updatedAt: String
    let avatar: String
    let parentId: String
    let spoiler: Bool
    let replies: [ComicComment]

    var displayName: String {
        if !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nickname
        }
        if !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return username
        }
        return userId.isEmpty ? "匿名用户" : "用户 \(userId)"
    }
}
