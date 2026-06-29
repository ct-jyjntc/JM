import Foundation

actor JMBoomAPI {
    static let shared = JMBoomAPI()

    private let apiVersion = "2.0.20"
    private let apiTokenSecret = "18comicAPP"
    private let contentTokenSecret = "18comicAPPContent"
    private let apiDataSecret = "185Hcomic3PAPP7R"
    private let apiRetryCount = 3
    private let mobileUserAgent = "Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Safari/537.36"
    private let webUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private let hostConfigSeed = "diosfjckwpqpdfjkvnqQjsik"
    private let fallbackEndpoints = [
        "https://www.cdnhjk.net",
        "https://www.cdngwc.cc",
        "https://www.cdngwc.net",
        "https://www.cdngwc.club",
        "https://www.cdnutc.me"
    ]
    private let hostConfigURLs = [
        "https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt",
        "https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt"
    ]
    private let blockedEndpointHosts: Set<String> = [
        "www.cdnaspa.vip",
        "www.cdnaspa.club",
        "www.cdnplaystation6.org",
        "www.cdnplaystation6.vip",
        "www.cdnplaystation6.cc"
    ]
    private let unsupportedHomeTitles = ["禁漫小说", "禁漫书库", "禁漫小說", "禁漫書庫"]

    private var imgHostCache: [String: String] = [:]
    private var officialEndpointCache: [String]?
    private var session = URLSession(configuration: .default)

    private func apiGetAuth() -> ApiAuth {
        .current(version: "", tokenSecret: apiTokenSecret, dataSecret: apiDataSecret)
    }

    private func apiPostAuth() -> ApiAuth {
        .current(version: apiVersion, tokenSecret: apiTokenSecret, dataSecret: apiDataSecret)
    }

    private func contentGetAuth() -> ApiAuth {
        .current(version: "", tokenSecret: contentTokenSecret, dataSecret: apiDataSecret)
    }

    func clearSession() {
        HTTPCookieStorage.shared.cookies?.forEach { cookie in
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        session = URLSession(configuration: session.configuration)
    }

    func exportSessionCookies(endpoint: String) throws -> [StoredHTTPCookie] {
        let endpoint = try normalizeEndpoint(endpoint)
        let hosts = persistentCookieHosts(for: endpoint)

        return (HTTPCookieStorage.shared.cookies ?? [])
            .filter { cookie in
                hosts.contains { host in cookie.domainMatches(host) }
            }
            .map(StoredHTTPCookie.init)
            .filter { !$0.isExpired }
    }

    func restoreSessionCookies(_ cookies: [StoredHTTPCookie], endpoint: String) throws {
        let endpoint = try normalizeEndpoint(endpoint)
        let hosts = persistentCookieHosts(for: endpoint)

        if !cookies.isEmpty {
            HTTPCookieStorage.shared.cookies?.forEach { cookie in
                if hosts.contains(where: { cookie.domainMatches($0) }) {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        }

        cookies
            .filter { !$0.isExpired }
            .compactMap(\.httpCookie)
            .forEach { HTTPCookieStorage.shared.setCookie($0) }

        session = URLSession(configuration: session.configuration)
    }

    func configureProxy(mode: ProxyMode, host: String, port: Int) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpCookieStorage = .shared

        if mode != .off {
            let proxyType = mode == .socks5 ? kCFProxyTypeSOCKS as String : kCFProxyTypeHTTP as String
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: mode == .http,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFStreamPropertySOCKSProxy as String: proxyType,
                kCFStreamPropertySOCKSProxyHost as String: host,
                kCFStreamPropertySOCKSProxyPort as String: port
            ]
        }

        session = URLSession(configuration: configuration)
    }

    func discoverEndpoints() async -> [ApiEndpointProbe] {
        var candidates = await officialEndpointHosts()
        candidates.append(contentsOf: fallbackEndpoints)
        candidates.removeAll { isBlockedEndpoint($0) }

        var seen = Set<String>()
        candidates = candidates.compactMap { endpoint in
            guard let normalized = try? normalizeEndpoint(endpoint), !seen.contains(normalized) else {
                return nil
            }
            seen.insert(normalized)
            return normalized
        }

        var probes: [ApiEndpointProbe] = []
        for endpoint in candidates {
            let started = Date.now
            do {
                let imgHost = try await remoteImageHost(endpoint: endpoint)
                let latency = Int(Date.now.timeIntervalSince(started) * 1_000)
                probes.append(ApiEndpointProbe(endpoint: endpoint, available: true, latencyMS: latency, imageHost: imgHost, error: nil))
            } catch {
                probes.append(ApiEndpointProbe(endpoint: endpoint, available: false, latencyMS: nil, imageHost: nil, error: error.localizedDescription))
            }
        }

        return probes.sorted {
            switch ($0.available, $1.available) {
            case (true, true): ($0.latencyMS ?? .max) < ($1.latencyMS ?? .max)
            case (true, false): true
            case (false, true): false
            case (false, false): $0.endpoint < $1.endpoint
            }
        }
    }

    func homeFeed(endpoint: String) async throws -> [HomeFeedSection] {
        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiGetAuth()
        let imgHost = try? await remoteImageHost(endpoint: endpoint)
        let payload = try await requestAPIValue(endpoint: endpoint, path: "promote", query: [], auth: auth)

        guard case .array(let sections) = payload else {
            throw APIError.payload("首页响应不是列表。")
        }

        return sections.compactMap { section in
            guard let object = section.objectValue else { return nil }
            let title = cleanHomeSectionTitle(object.string("title"))
            guard !unsupportedHomeTitles.contains(title), !title.isEmpty else {
                return nil
            }

            return HomeFeedSection(
                id: object.string("id"),
                title: title,
                slug: object.string("slug"),
                type: object.string("type"),
                filterValue: object.string("filter_val"),
                items: object.array("content").map { mapFeedComic($0, imgHost: imgHost) }
            )
        }
    }

    private func cleanHomeSectionTitle(_ title: String) -> String {
        let markerPattern = #"(右\s*滑|右\s*滑動|右\s*滑动|滑動|滑动)\s*(看\s*更多|查看\s*更多|更多)"#
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: markerPattern, options: [.regularExpression, .caseInsensitive]) {
            cleaned = String(cleaned[..<range.lowerBound])
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
    }

    func search(query: String, page: Int, endpoint: String, order: CategoryFeedOrder = .latest) async throws -> SearchAlbumsResult {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return SearchAlbumsResult(query: query, page: page, total: 0, endpoint: nil, redirectAid: nil, items: [])
        }

        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiGetAuth()
        let imgHost = try? await remoteImageHost(endpoint: endpoint)
        let payload = try await requestAPIValue(
            endpoint: endpoint,
            path: "search",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "o", value: order.rawValue),
                URLQueryItem(name: "search_query", value: query)
            ],
            auth: auth
        )

        guard let object = payload.objectValue else {
            throw APIError.payload("搜索响应不是对象。")
        }

        let items = object.array("content").map { item in
            let itemObject = item.objectValue ?? [:]
            let id = itemObject.string("id")
            var tags: [String] = []
            if let category = itemObject["category"]?.objectValue?.string("title"), !category.isEmpty {
                tags.append(category)
            }
            if let category = itemObject["category_sub"]?.objectValue?.string("title"), !category.isEmpty, !tags.contains(category) {
                tags.append(category)
            }
            for tag in itemObject["tags"]?.stringArrayValue ?? [] where !tags.contains(tag) {
                tags.append(tag)
            }

            return SearchAlbum(
                id: id,
                title: itemObject.string("name"),
                author: itemObject.string("author"),
                description: itemObject.string("description"),
                image: coverImageURL(imgHost: imgHost, comicId: id) ?? itemObject.string("image"),
                tags: tags,
                href: "\(endpoint)/album/\(id)",
                updatedAt: itemObject["update_at"]?.int64Value,
                isRedirect: false
            )
        }

        let redirectAid = object["redirect_aid"]?.stringValue
        let resolvedItems = items.isEmpty && redirectAid != nil
            ? [SearchAlbum(id: redirectAid ?? "", title: "JM\(redirectAid ?? "")", author: "", description: "", image: "", tags: [], href: "", updatedAt: nil, isRedirect: true)]
            : items

        return SearchAlbumsResult(
            query: object.string("search_query", fallback: query),
            page: page,
            total: Int(object["total"]?.uint32Value ?? 0),
            endpoint: endpoint,
            redirectAid: redirectAid,
            items: resolvedItems
        )
    }

    func comicDetail(comicId: String, endpoint: String) async throws -> ComicDetail {
        let comicId = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comicId.isEmpty else { throw APIError.missingData("作品 ID 为空。") }

        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiGetAuth()
        async let imgHost = try? remoteImageHost(endpoint: endpoint)
        async let payload = requestAPIValue(
            endpoint: endpoint,
            path: "album",
            query: [URLQueryItem(name: "id", value: comicId)],
            auth: auth
        )

        let (host, value) = try await (imgHost, payload)
        guard let object = value.objectValue, object["name"] != nil else {
            throw APIError.payload("当前条目可能是小说或书库内容，暂不支持漫画详情阅读。")
        }

        let id = object.string("id")
        return ComicDetail(
            id: id,
            title: object.string("name"),
            author: object["author"]?.stringArrayValue ?? [],
            description: object.string("description"),
            totalViews: object["total_views"]?.uint32Value ?? 0,
            likes: object["likes"]?.uint32Value ?? 0,
            commentTotal: object["comment_total"]?.uint32Value ?? 0,
            tags: object["tags"]?.stringArrayValue ?? [],
            actors: object["actors"]?.stringArrayValue ?? [],
            works: object["works"]?.stringArrayValue ?? [],
            isFavorite: object["is_favorite"]?.boolValue ?? false,
            liked: object["liked"]?.boolValue ?? false,
            relatedList: object.array("related_list").map { mapRelatedComic($0, imgHost: host) },
            series: object.array("series").map { item in
                let itemObject = item.objectValue ?? [:]
                return ComicChapter(id: itemObject.string("id"), title: itemObject.string("name"), sort: itemObject.string("sort"))
            },
            seriesId: object.string("series_id"),
            price: object["price"]?.uint32Value ?? 0,
            purchased: object["purchased"]?.boolValue ?? false,
            image: coverImageURL(imgHost: host, comicId: id) ?? ""
        )
    }

    func comicComments(comicId: String, page: Int, endpoint: String) async throws -> ComicCommentsResult {
        let comicId = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comicId.isEmpty else { throw APIError.missingData("作品 ID 为空。") }

        let page = max(1, page)
        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiGetAuth()
        async let imgHost = try? remoteImageHost(endpoint: endpoint)
        async let payload = requestAPIValue(
            endpoint: endpoint,
            path: "forum",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "aid", value: comicId),
                URLQueryItem(name: "mode", value: "manhua")
            ],
            auth: auth
        )
        let (host, value) = try await (imgHost, payload)
        let object = value.objectValue ?? [:]

        return ComicCommentsResult(
            endpoint: endpoint,
            page: page,
            total: Int(object["total"]?.uint32Value ?? 0),
            comments: object.array("list").map { mapComment($0, imgHost: host) }
        )
    }

    func postComicComment(comicId: String, content: String, parentId: String? = nil, endpoint: String) async throws -> CommentActionResult {
        let comicId = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comicId.isEmpty else { throw APIError.missingData("作品 ID 为空。") }
        guard !content.isEmpty else { throw APIError.missingData("评论内容为空。") }

        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiPostAuth()
        let fields = [
            URLQueryItem(name: "aid", value: comicId),
            URLQueryItem(name: "comment", value: content),
            URLQueryItem(name: "comment_id", value: parentId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "0")
        ]

        do {
            let payload = try await requestFormAPIValue(endpoint: endpoint, path: "comment", fields: fields, auth: auth)
            return CommentActionResult(endpoint: endpoint, message: try actionSuccessMessage(from: payload, fallback: "评论已发送"))
        } catch {
            return try await postWebAlbumComment(comicId: comicId, content: content, parentId: parentId, endpoint: endpoint)
        }
    }

    func toggleComicFavorite(comicId: String, currentFavorite: Bool, endpoint: String) async throws -> FavoriteToggleResult {
        let comicId = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comicId.isEmpty else { throw APIError.missingData("作品 ID 为空。") }

        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiPostAuth()
        let payload = try await requestFormAPIValue(
            endpoint: endpoint,
            path: "favorite",
            fields: [URLQueryItem(name: "aid", value: comicId)],
            auth: auth
        )
        _ = try actionSuccessMessage(from: payload, fallback: "收藏状态已更新")

        return FavoriteToggleResult(endpoint: endpoint, favorited: !currentFavorite)
    }

    func purchaseComic(comicId: String, endpoint: String) async throws -> PurchaseComicResult {
        let comicId = comicId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comicId.isEmpty else { throw APIError.missingData("作品 ID 为空。") }

        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiPostAuth()
        let payload = try await requestFormAPIValue(
            endpoint: endpoint,
            path: "coin_buy_comics",
            fields: [URLQueryItem(name: "id", value: comicId)],
            auth: auth
        )
        let message = try actionSuccessMessage(from: payload, fallback: "购买请求已提交")
        return PurchaseComicResult(endpoint: endpoint, message: message)
    }

    private func actionMessage(from payload: JSONValue) -> String? {
        if let object = payload.objectValue {
            for key in ["msg", "message", "error", "err"] {
                let value = object.string(key).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }

        if let message = payload.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return message
        }

        return nil
    }

    private func actionSuccessMessage(from payload: JSONValue, fallback: String) throws -> String {
        if let object = payload.objectValue {
            if object["err"]?.boolValue == true {
                throw APIError.api(object.string("msg", fallback: object.string("error", fallback: fallback)))
            }

            for key in ["error", "err"] {
                guard let value = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
                if ["0", "false", "null"].contains(value.lowercased()) { continue }
                throw APIError.api(value)
            }

            if let status = object["status"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty {
                let normalizedStatus = status.lowercased()
                if ["ok", "success", "true"].contains(normalizedStatus) {
                    return object.string("msg", fallback: object.string("message", fallback: fallback))
                }
                throw APIError.api(object.string("msg", fallback: object.string("message", fallback: status)))
            }

            for key in ["msg", "message"] {
                let message = object.string(key).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !message.isEmpty else { continue }
                guard !isNegativeActionMessage(message) else { throw APIError.api(message) }
                return message
            }

            return fallback
        }

        if let message = payload.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            guard !isNegativeActionMessage(message) else { throw APIError.api(message) }
            return message
        }

        return fallback
    }

    private func isPositiveActionMessage(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        if isNegativeActionMessage(normalized) {
            return false
        }

        return normalized.range(of: #"成功|完成|已購買|已购买|purchased|success|ok"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func isNegativeActionMessage(_ message: String) -> Bool {
        message.range(of: #"失敗|失败|錯誤|错误|非法|Not legal|not legal|error|denied|unauthorized|不足|未登入|未登录|請先|请先|不能|无法|失效"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func postWebAlbumComment(comicId: String, content: String, parentId: String?, endpoint: String) async throws -> CommentActionResult {
        var fields = [
            URLQueryItem(name: "video_id", value: comicId),
            URLQueryItem(name: "comment", value: content),
            URLQueryItem(name: "originator", value: ""),
            URLQueryItem(name: "status", value: "true")
        ]

        if let parentId, !parentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.removeAll { $0.name == "status" }
            fields.append(URLQueryItem(name: "comment_id", value: parentId))
            fields.append(URLQueryItem(name: "is_reply", value: "1"))
            fields.append(URLQueryItem(name: "forum_subject", value: "1"))
        }

        let payload = try await requestPlainFormValue(endpoint: endpoint, path: "ajax/album_comment", fields: fields)
        if let object = payload.objectValue {
            if object["err"]?.boolValue == false {
                return CommentActionResult(endpoint: endpoint, message: object.string("msg", fallback: "评论已发送"))
            }
            throw APIError.api(object.string("msg", fallback: object.string("error", fallback: "评论发送失败。")))
        }

        return CommentActionResult(endpoint: endpoint, message: payload.stringValue ?? "评论已发送")
    }

    func favoriteComics(endpoint: String, page: Int, folderId: String = "", order: String = "mr") async throws -> FavoriteListResult {
        let endpoint = try normalizeEndpoint(endpoint)
        let page = max(1, page)
        let order = order.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mr" : order.trimmingCharacters(in: .whitespacesAndNewlines)
        let auth = apiGetAuth()
        async let imgHost = try? remoteImageHost(endpoint: endpoint)
        async let payload = requestAPIValue(
            endpoint: endpoint,
            path: "favorite",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "folder_id", value: folderId.trimmingCharacters(in: .whitespacesAndNewlines)),
                URLQueryItem(name: "o", value: order)
            ],
            auth: auth
        )
        let (host, value) = try await (imgHost, payload)
        let object = value.objectValue ?? [:]
        let total = Int(object["total"]?.uint32Value ?? 0)
        let items = object.array("list").compactMap { value -> FeedComic? in
            let comic = mapFavoriteComic(value, imgHost: host)
            return comic.id.isEmpty ? nil : comic
        }

        return FavoriteListResult(
            endpoint: endpoint,
            page: page,
            total: total,
            hasMore: total > 0 ? page * 20 < total : items.count >= 20,
            folders: object.array("folder_list").compactMap(mapFavoriteFolder),
            items: items
        )
    }

    func login(username: String, password: String, endpoint: String) async throws -> LoginResult {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.missingData("请输入用户名和密码。")
        }

        let endpoint = await officialEndpointForDirectUse(preferred: endpoint)
        clearSession()
        let loginAuth = apiPostAuth()
        let result = try await requestFormAPIResult(
            endpoint: endpoint,
            path: "login",
            fields: [
                URLQueryItem(name: "username", value: username),
                URLQueryItem(name: "password", value: password)
            ],
            auth: loginAuth
        )

        let host = try? await remoteImageHost(endpoint: result.endpoint)
        return LoginResult(endpoint: result.endpoint, user: mapUserProfile(result.value, imgHost: host))
    }

    func getSignInData(userId: UInt32, endpoint: String) async throws -> SignInDataResult {
        guard userId > 0 else { throw APIError.missingData("用户 ID 为空。") }

        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiGetAuth()
        let payload = try await requestAPIValue(
            endpoint: endpoint,
            path: "daily",
            query: [URLQueryItem(name: "user_id", value: String(userId))],
            auth: auth
        )

        return mapSignInData(payload, endpoint: endpoint)
    }

    func signIn(userId: UInt32, dailyId: UInt32, endpoint: String) async throws -> SignInResult {
        guard userId > 0, dailyId > 0 else { throw APIError.missingData("签到信息不完整。") }

        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiPostAuth()
        let payload = try await requestFormAPIValue(
            endpoint: endpoint,
            path: "daily_chk",
            fields: [
                URLQueryItem(name: "user_id", value: String(userId)),
                URLQueryItem(name: "daily_id", value: String(dailyId))
            ],
            auth: auth
        )
        let object = payload.objectValue ?? [:]

        return SignInResult(endpoint: endpoint, message: object.string("msg"))
    }

    func weekFilters(endpoint: String) async throws -> WeekFiltersResult {
        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiGetAuth()
        let payload = try await requestAPIValue(endpoint: endpoint, path: "week", query: [], auth: auth)
        guard let object = payload.objectValue else { throw APIError.payload("周榜筛选响应不是对象。") }

        let categories = object.array("categories").map { value in
            let item = value.objectValue ?? [:]
            let time = item.string("time")
            let title = item.string("title")
            return WeekCategory(id: item.string("id"), time: time, title: title, label: time.isEmpty ? title : "\(title) (\(time))")
        }
        let types = object.array("type").map { value in
            let item = value.objectValue ?? [:]
            return WeekType(id: item.string("id"), title: item.string("title"))
        }

        return WeekFiltersResult(endpoint: endpoint, categories: categories, types: types)
    }

    func weekItems(endpoint: String, page: Int, categoryId: String, typeId: String) async throws -> WeekItemsResult {
        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiGetAuth()
        async let imgHost = try? remoteImageHost(endpoint: endpoint)
        async let payload = requestAPIValue(
            endpoint: endpoint,
            path: "week/filter",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "id", value: categoryId),
                URLQueryItem(name: "type", value: typeId)
            ],
            auth: auth
        )
        let (host, value) = try await (imgHost, payload)
        guard let object = value.objectValue else { throw APIError.payload("周榜内容响应不是对象。") }

        return WeekItemsResult(
            endpoint: endpoint,
            page: page,
            total: Int(object["total"]?.uint32Value ?? 0),
            items: object.array("list").map { mapFeedComic($0, imgHost: host) }
        )
    }

    func categoryMetadata(endpoint: String) async throws -> CategoryMetadataResult {
        var lastError: Error?
        for candidate in await readerEndpointCandidates(preferred: endpoint) {
            do {
                return try await categoryMetadataOnce(endpoint: candidate)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? APIError.network("分类元数据接口不可用。")
    }

    private func categoryMetadataOnce(endpoint: String) async throws -> CategoryMetadataResult {
        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiGetAuth()
        let payload = try await requestAPIValue(endpoint: endpoint, path: "categories", query: [], auth: auth)
        guard let object = payload.objectValue else { throw APIError.payload("分类元数据响应不是对象。") }

        let categories = object.array("categories").map { value in
            let item = value.objectValue ?? [:]
            return CategoryDefinition(
                id: "\(item.string("id"))-\(item.string("slug", fallback: item.string("name")))",
                name: item.string("name"),
                slug: item.string("slug"),
                type: item.string("type"),
                totalAlbums: item.string("total_albums"),
                subcategories: item.array("sub_categories").map { subValue in
                    let sub = subValue.objectValue ?? [:]
                    return CategoryDefinition.Subcategory(
                        id: sub.string("CID", fallback: sub.string("id")),
                        name: sub.string("name"),
                        slug: sub.string("slug")
                    )
                }
            )
        }

        let blocks = object.array("blocks").map { value in
            let item = value.objectValue ?? [:]
            return CategoryBlock(title: item.string("title"), tags: item["content"]?.stringArrayValue ?? [])
        }

        return CategoryMetadataResult(endpoint: endpoint, categories: categories, blocks: blocks)
    }

    func categoryFeed(endpoint: String, page: Int, order: CategoryFeedOrder, categorySlug: String? = nil) async throws -> CategoryFeedResult {
        try await categoryFeed(endpoint: endpoint, page: page, orderRawValue: order.rawValue, categorySlug: categorySlug)
    }

    func categoryFeed(endpoint: String, page: Int, orderRawValue: String, categorySlug: String? = nil) async throws -> CategoryFeedResult {
        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiGetAuth()
        let order = orderRawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CategoryFeedOrder.latest.rawValue : orderRawValue
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "order", value: ""),
            URLQueryItem(name: "o", value: order)
        ]
        if let categorySlug = categorySlug?.trimmingCharacters(in: .whitespacesAndNewlines), !categorySlug.isEmpty {
            queryItems.append(URLQueryItem(name: "c", value: categorySlug))
        }

        async let imgHost = try? remoteImageHost(endpoint: endpoint)
        async let payload = requestAPIValue(
            endpoint: endpoint,
            path: "categories/filter",
            query: queryItems,
            auth: auth
        )
        let (host, value) = try await (imgHost, payload)
        guard let object = value.objectValue else { throw APIError.payload("分类内容响应不是对象。") }

        return CategoryFeedResult(
            endpoint: endpoint,
            page: page,
            total: Int(object["total"]?.uint32Value ?? 0),
            items: object.array("content").map { mapFeedComic($0, imgHost: host) },
            tags: object["tags"]?.stringArrayValue ?? []
        )
    }

    func promoteList(endpoint: String, page: Int, id: String) async throws -> PromoteListResult {
        let endpoint = try normalizeEndpoint(endpoint)
        let auth = apiGetAuth()
        async let imgHost = try? remoteImageHost(endpoint: endpoint)
        async let payload = requestAPIValue(
            endpoint: endpoint,
            path: "promote_list",
            query: [
                URLQueryItem(name: "page", value: String(max(1, page))),
                URLQueryItem(name: "id", value: id)
            ],
            auth: auth
        )

        let (host, value) = try await (imgHost, payload)
        guard let object = value.objectValue else { throw APIError.payload("频道响应不是对象。") }

        return PromoteListResult(
            endpoint: endpoint,
            page: page,
            total: Int(object["total"]?.uint32Value ?? 0),
            items: object.array("list").map { mapFeedComic($0, imgHost: host) }
        )
    }

    func downloadImageBytes(_ url: URL, referer: String? = nil) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "accept")
        request.setValue(mobileUserAgent, forHTTPHeaderField: "user-agent")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "referer")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, requestName: url.absoluteString)
        return data
    }

    func fetchReaderHTML(readId: String, endpoint: String, shunt: String) async throws -> ReaderHTMLResult {
        var lastError: Error?
        for candidate in await readerEndpointCandidates(preferred: endpoint) {
            do {
                let html = try await fetchReaderHTMLOnce(readId: readId, endpoint: candidate, shunt: shunt)
                return ReaderHTMLResult(endpoint: candidate, html: html)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? APIError.network("阅读接口不可用。")
    }

    private func fetchReaderHTMLOnce(readId: String, endpoint: String, shunt: String) async throws -> String {
        let endpoint = try normalizeEndpoint(endpoint)
        let auth = contentGetAuth()
        var components = URLComponents(string: "\(endpoint)/chapter_view_template")
        components?.queryItems = [
            URLQueryItem(name: "id", value: readId),
            URLQueryItem(name: "app_img_shunt", value: shunt),
            URLQueryItem(name: "mode", value: "vertical"),
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "express", value: "off"),
            URLQueryItem(name: "v", value: String(Int(Date.now.timeIntervalSince1970)))
        ]
        guard let url = components?.url else { throw APIError.unsupportedEndpoint(endpoint) }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "accept")
        request.setValue(mobileUserAgent, forHTTPHeaderField: "user-agent")
        request.setValue(auth.token, forHTTPHeaderField: "token")
        request.setValue(auth.tokenParameter, forHTTPHeaderField: "tokenparam")
        applyOfficialHeaders(to: &request, endpoint: endpoint)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, requestName: url.absoluteString)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func readerEndpointCandidates(preferred: String) async -> [String] {
        await apiEndpointCandidates(preferred: preferred)
    }

    private func apiEndpointCandidates(preferred: String) async -> [String] {
        var seen = Set<String>()
        let discovered = await officialEndpointHosts()
        let officialCandidates = (discovered + fallbackEndpoints).filter { !isBlockedEndpoint($0) }
        let normalizedOfficialEndpoints = Set(officialCandidates.compactMap { try? normalizeEndpoint($0) })
        let normalizedPreferred = try? normalizeEndpoint(preferred)
        let preferredCandidates: [String]
        if let normalizedPreferred, normalizedOfficialEndpoints.contains(normalizedPreferred), !isBlockedEndpoint(normalizedPreferred) {
            preferredCandidates = [normalizedPreferred]
        } else {
            preferredCandidates = []
        }

        return (preferredCandidates + officialCandidates).compactMap { value in
            guard let normalized = try? normalizeEndpoint(value), !seen.contains(normalized) else {
                return nil
            }
            seen.insert(normalized)
            return normalized
        }
    }

    private func isBlockedEndpoint(_ endpoint: String) -> Bool {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/\/+$/, with: "")
        let value = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
        guard let host = URLComponents(string: value)?.host?.lowercased() else { return false }
        return blockedEndpointHosts.contains(host)
    }

    private func officialEndpointForDirectUse(preferred: String) async -> String {
        let candidates = await apiEndpointCandidates(preferred: preferred)
        if let endpoint = candidates.first {
            return endpoint
        }
        return fallbackEndpoints[0]
    }

    private func officialEndpointHosts() async -> [String] {
        if let officialEndpointCache {
            return officialEndpointCache
        }
        guard let hosts = try? await fetchHostConfig(), !hosts.isEmpty else {
            return []
        }
        let filteredHosts = hosts.filter { !isBlockedEndpoint($0) }
        officialEndpointCache = filteredHosts
        return filteredHosts
    }

    private func remoteImageHost(endpoint: String) async throws -> String {
        if let cached = imgHostCache[endpoint] {
            return cached
        }

        let auth = apiGetAuth()
        let payload = try await requestAPIValue(
            endpoint: endpoint,
            path: "setting",
            query: [
                URLQueryItem(name: "app_img_shunt", value: "1"),
                URLQueryItem(name: "t", value: String(auth.timestamp))
            ],
            auth: auth
        )
        guard let imgHost = payload.objectValue?.string("img_host"), !imgHost.isEmpty else {
            throw APIError.missingData("接口没有返回图片主机。")
        }
        imgHostCache[endpoint] = imgHost
        return imgHost
    }

    private func fetchHostConfig() async throws -> [String] {
        var lastError: Error?
        for value in hostConfigURLs {
            guard let url = URL(string: value) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                try validate(response: response, requestName: value)
                let body = String(data: data, encoding: .utf8) ?? ""
                let normalized = body.filter { $0.isASCII && ($0.isLetter || $0.isNumber || ["+", "/", "="].contains($0)) }
                let key = CryptoBox.md5Hex(hostConfigSeed)
                let decrypted = try CryptoBox.aes256ECBDecryptBase64(String(normalized), key: key)
                let payload = try JSONDecoder().decode(HostConfigPayload.self, from: Data(decrypted.utf8))
                return payload.server
            } catch {
                lastError = error
            }
        }
        throw lastError ?? APIError.network("主机配置地址不可用。")
    }

    private func requestAPIValue(endpoint: String, path: String, query: [URLQueryItem], auth: ApiAuth) async throws -> JSONValue {
        var lastError: Error?
        for candidate in await apiEndpointCandidates(preferred: endpoint) {
            do {
                var components = URLComponents(string: "\(candidate)/\(path)")
                components?.queryItems = query.isEmpty ? nil : query
                guard let url = components?.url else { throw APIError.unsupportedEndpoint(candidate) }

                var request = URLRequest(url: url, timeoutInterval: 12)
                request.setValue("application/json", forHTTPHeaderField: "accept")
                request.setValue(mobileUserAgent, forHTTPHeaderField: "user-agent")
                request.setValue(auth.token, forHTTPHeaderField: "token")
                request.setValue(auth.tokenParameter, forHTTPHeaderField: "tokenparam")
                applyOfficialHeaders(to: &request, endpoint: candidate)

                return try await requestPreparedAPIValue(request: request, auth: auth, requestName: url.absoluteString)
            } catch {
                lastError = error
                guard shouldRetryAPIRequest(after: error) else { throw error }
            }
        }

        throw lastError ?? APIError.network("\(path): 官方 API 线路不可用。")
    }

    private func requestFormAPIValue(endpoint: String, path: String, fields: [URLQueryItem], auth: ApiAuth) async throws -> JSONValue {
        try await requestFormAPIResult(endpoint: endpoint, path: path, fields: fields, auth: auth).value
    }

    private func requestFormAPIResult(endpoint: String, path: String, fields: [URLQueryItem], auth: ApiAuth) async throws -> APIValueResult {
        var lastError: Error?
        for candidate in await apiEndpointCandidates(preferred: endpoint) {
            do {
                guard let url = URL(string: "\(candidate)/\(path)") else { throw APIError.unsupportedEndpoint(candidate) }
                var components = URLComponents()
                components.queryItems = fields

                var request = URLRequest(url: url, timeoutInterval: 12)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "accept")
                request.setValue(mobileUserAgent, forHTTPHeaderField: "user-agent")
                request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "content-type")
                request.setValue(auth.token, forHTTPHeaderField: "token")
                request.setValue(auth.tokenParameter, forHTTPHeaderField: "tokenparam")
                applyOfficialHeaders(to: &request, endpoint: candidate)
                request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

                let value = try await requestPreparedAPIValue(request: request, auth: auth, requestName: url.absoluteString)
                return APIValueResult(endpoint: candidate, value: value)
            } catch {
                lastError = error
                guard shouldRetryAPIRequest(after: error) else { throw error }
            }
        }

        throw lastError ?? APIError.network("\(path): 官方 API 线路不可用。")
    }

    private func requestMultipartAPIValue(endpoint: String, path: String, fields: [URLQueryItem], auth: ApiAuth) async throws -> JSONValue {
        var lastError: Error?
        for candidate in await apiEndpointCandidates(preferred: endpoint) {
            do {
                guard let url = URL(string: "\(candidate)/\(path)") else { throw APIError.unsupportedEndpoint(candidate) }
                let boundary = "Boundary-\(UUID().uuidString)"
                var body = Data()

                for field in fields {
                    body.append("--\(boundary)\r\n")
                    body.append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
                    body.append("\(field.value ?? "")\r\n")
                }
                body.append("--\(boundary)--\r\n")

                var request = URLRequest(url: url, timeoutInterval: 12)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "accept")
                request.setValue(mobileUserAgent, forHTTPHeaderField: "user-agent")
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
                request.setValue(auth.token, forHTTPHeaderField: "token")
                request.setValue(auth.tokenParameter, forHTTPHeaderField: "tokenparam")
                applyOfficialHeaders(to: &request, endpoint: candidate)
                request.httpBody = body

                return try await requestPreparedAPIValue(request: request, auth: auth, requestName: url.absoluteString)
            } catch {
                lastError = error
                guard shouldRetryAPIRequest(after: error) else { throw error }
            }
        }

        throw lastError ?? APIError.network("\(path): 官方 API 线路不可用。")
    }

    private func requestPlainFormValue(endpoint: String, path: String, fields: [URLQueryItem]) async throws -> JSONValue {
        guard let url = URL(string: "\(endpoint)/\(path)") else { throw APIError.unsupportedEndpoint(endpoint) }
        var components = URLComponents()
        components.queryItems = fields

        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "x-requested-with")
        request.setValue(webUserAgent, forHTTPHeaderField: "user-agent")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "content-type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, requestName: url.absoluteString)

        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            let preview = String(data: data.prefix(180), encoding: .utf8) ?? ""
            throw APIError.decode("\(url.absoluteString): \(error.localizedDescription). \(preview)")
        }
    }

    private func applyOfficialHeaders(to request: inout URLRequest, endpoint: String) {
        guard let host = URLComponents(string: endpoint)?.host else { return }
        let origin = "https://\(host)"
        request.setValue(host, forHTTPHeaderField: "Authority")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(origin, forHTTPHeaderField: "Referer")
    }

    private func requestPreparedAPIValue(request: URLRequest, auth: ApiAuth, requestName: String) async throws -> JSONValue {
        var lastError: Error?
        for attempt in 0...apiRetryCount {
            do {
                return try await requestPreparedAPIValueOnce(request: request, auth: auth, requestName: requestName)
            } catch let error as CancellationError {
                throw error
            } catch {
                lastError = error
                guard attempt < apiRetryCount, shouldRetryAPIRequest(after: error) else {
                    throw error
                }
                try await Task.sleep(for: retryDelay(attempt: attempt))
            }
        }

        throw lastError ?? APIError.network("\(requestName): 请求失败。")
    }

    private func requestPreparedAPIValueOnce(request: URLRequest, auth: ApiAuth, requestName: String) async throws -> JSONValue {
        let (data, response) = try await session.data(for: request)
        try validate(response: response, requestName: requestName)
        let envelope = try decodeEnvelope(data: data, auth: auth, requestName: requestName)

        if let message = envelope.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            throw apiError(message: message, requestName: requestName)
        }

        guard envelope.code == 200 else {
            throw apiError(message: envelope.errorMessage ?? "接口返回 code \(envelope.code)。", requestName: requestName)
        }
        guard let data = envelope.data else {
            throw APIError.missingData("接口没有返回 data。")
        }

        if case .string(let encrypted) = data {
            let decrypted = try CryptoBox.aes256ECBDecryptBase64(encrypted, key: auth.responseKey)
            return try JSONDecoder().decode(JSONValue.self, from: Data(decrypted.utf8))
        }

        return data
    }

    private func shouldRetryAPIRequest(after error: Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let urlError = error as? URLError {
            return urlError.code != .cancelled && urlError.code != .badURL
        }

        guard let apiError = error as? APIError else {
            return false
        }

        switch apiError {
        case .http, .decode, .missingData, .network:
            return true
        case .api, .authenticationRequired, .payload, .unsupportedEndpoint:
            return false
        }
    }

    private func retryDelay(attempt: Int) -> Duration {
        .milliseconds(350 * (attempt + 1))
    }

    private func decodeEnvelope(data: Data, auth: ApiAuth, requestName: String) throws -> APIEnvelope {
        do {
            return try JSONDecoder().decode(APIEnvelope.self, from: data)
        } catch {
            let preview = String(data: data.prefix(180), encoding: .utf8) ?? ""
            if isHTMLResponse(preview) {
                throw APIError.network("\(requestName): 当前线路返回发布页，不是移动 API。")
            }
            throw APIError.decode("\(requestName): \(error.localizedDescription). \(preview)")
        }
    }

    private func isHTMLResponse(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("<!doctype html")
            || normalized.hasPrefix("<html")
            || normalized.hasPrefix("<meta")
            || normalized.contains("<title>")
            || normalized.contains("禁漫天堂發布頁")
            || normalized.contains("app下载")
    }

    private func validate(response: URLResponse, requestName: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401, !isLoginRequest(requestName) {
                throw authenticationRequiredError()
            }
            throw APIError.http("\(requestName): HTTP \(http.statusCode)")
        }
    }

    private func apiError(message: String, requestName: String) -> APIError {
        if !isLoginRequest(requestName), isAuthenticationExpiredMessage(message) {
            return authenticationRequiredError()
        }
        return .api(message)
    }

    private func authenticationRequiredError() -> APIError {
        NotificationCenter.default.post(name: .jmAuthenticationExpired, object: nil)
        return .authenticationRequired("登录状态已过期，请重新登录。")
    }

    private func isLoginRequest(_ requestName: String) -> Bool {
        URLComponents(string: requestName)?.path == "/login"
    }

    private func isAuthenticationExpiredMessage(_ message: String) -> Bool {
        message.range(
            of: #"HTTP\s*401|unauthorized|未登入|未登录|請先登入|请先登录|請先登錄|请先登錄|登入會員|登录会员|登錄會員"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func normalizeEndpoint(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/\/+$/, with: "")
        let candidate = trimmed.isEmpty ? fallbackEndpoints[0] : trimmed
        let endpoint = candidate.hasPrefix("http://") || candidate.hasPrefix("https://") ? candidate : "https://\(candidate)"
        guard let url = URLComponents(string: endpoint), let scheme = url.scheme, let host = url.host, ["http", "https"].contains(scheme) else {
            throw APIError.unsupportedEndpoint(endpoint)
        }

        var normalized = "\(scheme)://\(host)"
        if let port = url.port {
            normalized += ":\(port)"
        }
        return normalized
    }

    private func persistentCookieHosts(for endpoint: String) -> Set<String> {
        var hosts: Set<String> = ["18comic.vip", "www.18comic.vip"]
        for value in [endpoint] + fallbackEndpoints + (officialEndpointCache ?? []) {
            if let host = URLComponents(string: value)?.host {
                hosts.insert(host)
            }
        }
        return hosts
    }

    private func mapFeedComic(_ value: JSONValue, imgHost: String?) -> FeedComic {
        let object = value.objectValue ?? [:]
        let id = object.string("id")
        var tags: [String] = []
        if let category = object["category"]?.objectValue?.string("title"), !category.isEmpty {
            tags.append(category)
        }
        if let category = object["category_sub"]?.objectValue?.string("title"), !category.isEmpty, !tags.contains(category) {
            tags.append(category)
        }
        for tag in object["tags"]?.stringArrayValue ?? [] where !tags.contains(tag) {
            tags.append(tag)
        }

        return FeedComic(
            id: id,
            title: object.string("name"),
            author: object.string("author"),
            description: object.string("description"),
            image: coverImageURL(imgHost: imgHost, comicId: id) ?? object.string("image"),
            tags: tags,
            updatedAt: object["update_at"]?.int64Value
        )
    }

    private func mapRelatedComic(_ value: JSONValue, imgHost: String?) -> RelatedComic {
        let object = value.objectValue ?? [:]
        let id = object.string("id")
        return RelatedComic(
            id: id,
            title: object.string("name"),
            author: object.string("author"),
            image: coverImageURL(imgHost: imgHost, comicId: id) ?? object.string("image")
        )
    }

    private func mapFavoriteComic(_ value: JSONValue, imgHost: String?) -> FeedComic {
        let object = value.objectValue ?? [:]
        let id = object.string("AID", fallback: object.string("aid", fallback: object.string("id")))
        var tags: [String] = []
        if let category = object["category"]?.objectValue?.string("title"), !category.isEmpty {
            tags.append(category)
        }
        if let category = object["category_sub"]?.objectValue?.string("title"), !category.isEmpty, !tags.contains(category) {
            tags.append(category)
        }
        for tag in object["tags"]?.stringArrayValue ?? [] where !tags.contains(tag) {
            tags.append(tag)
        }

        return FeedComic(
            id: id,
            title: object.string("name"),
            author: object.string("author"),
            description: object.string("description"),
            image: coverImageURL(imgHost: imgHost, comicId: id) ?? object.string("image"),
            tags: tags,
            updatedAt: object["update_at"]?.int64Value
        )
    }

    private func mapFavoriteFolder(_ value: JSONValue) -> FavoriteFolder? {
        let object = value.objectValue ?? [:]
        let id = object.string("FID", fallback: object.string("id", fallback: object.string("folder_id")))
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return FavoriteFolder(id: id, name: object.string("name", fallback: "收藏夹 \(id)"))
    }

    private func mapComment(_ value: JSONValue, imgHost: String?) -> ComicComment {
        let object = value.objectValue ?? [:]
        let avatar = object.string("photo")
        return ComicComment(
            id: object.string("CID", fallback: object.string("cid")),
            comicId: object.string("AID", fallback: object.string("aid")).nilIfBlank,
            userId: object.string("UID", fallback: object.string("uid")),
            username: object.string("username"),
            nickname: object.string("nickname"),
            content: object.string("content"),
            likeCount: object["likes"]?.uint32Value ?? 0,
            time: object.string("addtime"),
            updatedAt: object.string("update_at"),
            avatar: userAvatarURL(imgHost: imgHost, photo: avatar) ?? "",
            parentId: object.string("parent_CID", fallback: object.string("parent_cid")),
            spoiler: object["spoiler"]?.boolValue ?? false,
            replies: object.array("replys").map { mapComment($0, imgHost: imgHost) }
        )
    }

    private func mapUserProfile(_ value: JSONValue, imgHost: String?) -> UserProfile {
        let object = value.objectValue ?? [:]
        let avatar = object.string("photo")
        return UserProfile(
            id: object["uid"]?.uint32Value ?? 0,
            username: object.string("username"),
            email: object.string("email"),
            avatar: avatar,
            avatarURL: userAvatarURL(imgHost: imgHost, photo: avatar) ?? "",
            level: object["level"]?.uint32Value ?? 0,
            levelName: object.string("level_name"),
            currentLevelExp: object["exp"]?.uint32Value ?? 0,
            nextLevelExp: object["nextLevelExp"]?.uint32Value ?? 0,
            expPercent: object["expPercent"]?.doubleValue ?? 0,
            currentCollectCount: object["album_favorites"]?.uint32Value ?? 0,
            maxCollectCount: object["album_favorites_max"]?.uint32Value ?? 0,
            jCoin: object["coin"]?.uint32Value ?? 0
        )
    }

    private func mapSignInData(_ value: JSONValue, endpoint: String) -> SignInDataResult {
        let object = value.objectValue ?? [:]
        let flatRecords = object.array("record").flatMap { recordValue -> [JSONValue] in
            if case .array(let records) = recordValue {
                return records
            }
            return [recordValue]
        }

        return SignInDataResult(
            endpoint: endpoint,
            dailyId: object["daily_id"]?.uint32Value ?? 0,
            threeDaysCoin: object["three_days_coin"]?.uint32Value ?? 0,
            threeDaysExp: object["three_days_exp"]?.uint32Value ?? 0,
            sevenDaysCoin: object["seven_days_coin"]?.uint32Value ?? 0,
            sevenDaysExp: object["seven_days_exp"]?.uint32Value ?? 0,
            eventName: object.string("event_name"),
            currentProgress: object.string("currentProgress"),
            backgroundPC: object.string("background_pc"),
            backgroundPhone: object.string("background_phone"),
            records: flatRecords.enumerated().map { index, value in
                let record = value.objectValue ?? [:]
                return SignInRecord(
                    day: UInt32(index + 1),
                    date: record.string("date"),
                    signed: record["signed"]?.boolValue ?? false,
                    bonus: record["bonus"]?.boolValue ?? false
                )
            }
        )
    }

    private func coverImageURL(imgHost: String?, comicId: String) -> String? {
        guard let imgHost = imgHost?.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/\/+$/, with: ""), !imgHost.isEmpty else {
            return nil
        }
        return "\(imgHost)/media/albums/\(comicId)_3x4.jpg"
    }

    private func userAvatarURL(imgHost: String?, photo: String) -> String? {
        let photo = photo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !photo.isEmpty else { return nil }
        if photo.hasPrefix("http://") || photo.hasPrefix("https://") {
            return photo
        }
        guard let imgHost = imgHost?.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/\/+$/, with: ""), !imgHost.isEmpty else {
            return nil
        }
        return photo.hasPrefix("/") ? "\(imgHost)\(photo)" : "\(imgHost)/media/users/\(photo)"
    }
}

struct ApiEndpointProbe: Identifiable, Hashable, Sendable {
    var id: String { endpoint }

    let endpoint: String
    let available: Bool
    let latencyMS: Int?
    let imageHost: String?
    let error: String?
}

struct SearchAlbumsResult: Sendable {
    let query: String
    let page: Int
    let total: Int
    let endpoint: String?
    let redirectAid: String?
    let items: [SearchAlbum]
}

struct WeekFiltersResult: Sendable {
    let endpoint: String
    let categories: [WeekCategory]
    let types: [WeekType]
}

struct WeekItemsResult: Sendable {
    let endpoint: String
    let page: Int
    let total: Int
    let items: [FeedComic]
}

struct CategoryMetadataResult: Sendable {
    let endpoint: String
    let categories: [CategoryDefinition]
    let blocks: [CategoryBlock]
}

struct CategoryDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let slug: String
    let type: String
    let totalAlbums: String
    let subcategories: [Subcategory]

    struct Subcategory: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let slug: String
    }
}

struct CategoryBlock: Identifiable, Hashable, Sendable {
    var id: String { title }

    let title: String
    let tags: [String]
}

struct PromoteListResult: Sendable {
    let endpoint: String
    let page: Int
    let total: Int
    let items: [FeedComic]
}

struct WeekCategory: Identifiable, Hashable, Sendable {
    let id: String
    let time: String
    let title: String
    let label: String
}

struct WeekType: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
}

enum CategoryFeedOrder: String, CaseIterable, Identifiable, Sendable {
    case latest = "mr"
    case mostViewed = "mv"
    case mostLiked = "tf"
    case images = "mp"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: "最新"
        case .mostViewed: "最多观看"
        case .mostLiked: "最多收藏"
        case .images: "最多图片"
        }
    }
}

struct CategoryFeedResult: Sendable {
    let endpoint: String
    let page: Int
    let total: Int
    let items: [FeedComic]
    let tags: [String]
}

struct ReaderHTMLResult: Sendable {
    let endpoint: String
    let html: String
}

private struct HostConfigPayload: Decodable {
    let server: [String]

    enum CodingKeys: String, CodingKey {
        case server = "Server"
    }
}

private struct APIEnvelope: Decodable {
    let code: Int
    let data: JSONValue?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case code
        case data
        case errorMessage = "errorMsg"
    }
}

private struct APIValueResult: Sendable {
    let endpoint: String
    let value: JSONValue
}

private struct ApiAuth: Sendable {
    let timestamp: Int
    let token: String
    let tokenParameter: String
    let responseKey: String

    static func current(version: String, tokenSecret: String, dataSecret: String) -> Self {
        let timestamp = Int(Date.now.timeIntervalSince1970)
        return Self(
            timestamp: timestamp,
            token: CryptoBox.md5Hex("\(timestamp)\(tokenSecret)"),
            tokenParameter: "\(timestamp),\(version)",
            responseKey: CryptoBox.md5Hex("\(timestamp)\(dataSecret)")
        )
    }
}

enum APIError: LocalizedError {
    case api(String)
    case authenticationRequired(String)
    case decode(String)
    case http(String)
    case missingData(String)
    case network(String)
    case payload(String)
    case unsupportedEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .api(let message), .authenticationRequired(let message), .decode(let message), .http(let message), .missingData(let message), .network(let message), .payload(let message):
            message
        case .unsupportedEndpoint(let endpoint):
            "不支持的接口地址：\(endpoint)"
        }
    }
}

extension Notification.Name {
    static let jmAuthenticationExpired = Notification.Name("JMAuthenticationExpired")
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String, fallback: String = "") -> String {
        self[key]?.stringValue ?? fallback
    }

    func array(_ key: String) -> [JSONValue] {
        guard case .array(let values) = self[key] else { return [] }
        return values
    }
}

private extension JSONValue {
    var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .bool(let value): value ? 1 : 0
        case .array, .object, .null: nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension HTTPCookie {
    func domainMatches(_ host: String) -> Bool {
        let normalizedDomain = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let normalizedHost = host.lowercased()
        return normalizedHost == normalizedDomain || normalizedHost.hasSuffix(".\(normalizedDomain)")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(contentsOf: string.utf8)
    }
}
