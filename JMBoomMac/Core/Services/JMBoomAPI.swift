import Foundation

actor JMBoomAPI {
    static let shared = JMBoomAPI()

    private let apiVersion = "2.0.20"
    private let apiSecret = "185Hcomic3PAPP7R"
    private let apiRetryCount = 3
    private let hostConfigSeed = "diosfjckwpqpdfjkvnqQjsik"
    private let fallbackEndpoints = ["https://www.cdnhth.club", "https://www.cdnhjk.net"]
    private let hostConfigURLs = [
        "https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt",
        "https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt"
    ]
    private let unsupportedHomeTitles = ["禁漫小说", "禁漫书库"]

    private var imgHostCache: [String: String] = [:]
    private var session = URLSession(configuration: .default)

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
        var candidates = fallbackEndpoints

        if let hosts = try? await fetchHostConfig() {
            candidates.append(contentsOf: hosts)
        }

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
        let auth = ApiAuth.current(version: apiVersion, secret: apiSecret)
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

    func search(query: String, page: Int, endpoint: String) async throws -> SearchAlbumsResult {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return SearchAlbumsResult(query: query, page: page, total: 0, endpoint: nil, redirectAid: nil, items: [])
        }

        let endpoint = try normalizeEndpoint(endpoint)
        let auth = ApiAuth.current(version: apiVersion, secret: apiSecret)
        let imgHost = try? await remoteImageHost(endpoint: endpoint)
        let payload = try await requestAPIValue(
            endpoint: endpoint,
            path: "search",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "o", value: "mr"),
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
        let auth = ApiAuth.current(version: apiVersion, secret: apiSecret)
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

    func weekFilters(endpoint: String) async throws -> WeekFiltersResult {
        let endpoint = try normalizeEndpoint(endpoint)
        let auth = ApiAuth.current(version: apiVersion, secret: apiSecret)
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
        let auth = ApiAuth.current(version: apiVersion, secret: apiSecret)
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

    func categoryFeed(endpoint: String, page: Int, order: CategoryFeedOrder) async throws -> CategoryFeedResult {
        let endpoint = try normalizeEndpoint(endpoint)
        let auth = ApiAuth.current(version: apiVersion, secret: apiSecret)
        async let imgHost = try? remoteImageHost(endpoint: endpoint)
        async let payload = requestAPIValue(
            endpoint: endpoint,
            path: "categories/filter",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "o", value: order.rawValue)
            ],
            auth: auth
        )
        let (host, value) = try await (imgHost, payload)
        guard let object = value.objectValue else { throw APIError.payload("分类内容响应不是对象。") }

        return CategoryFeedResult(
            endpoint: endpoint,
            page: page,
            total: Int(object["total"]?.uint32Value ?? 0),
            items: object.array("content").map { mapFeedComic($0, imgHost: host) }
        )
    }

    func downloadImageBytes(_ url: URL, referer: String? = nil) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "accept")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "referer")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, requestName: url.absoluteString)
        return data
    }

    func fetchReaderHTML(readId: String, endpoint: String, shunt: String) async throws -> ReaderHTMLResult {
        var lastError: Error?
        for candidate in readerEndpointCandidates(preferred: endpoint) {
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
        let auth = ApiAuth.current(version: apiVersion, secret: apiSecret)
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
        request.setValue(auth.token, forHTTPHeaderField: "token")
        request.setValue(auth.tokenParameter, forHTTPHeaderField: "tokenparam")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, requestName: url.absoluteString)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func readerEndpointCandidates(preferred: String) -> [String] {
        var seen = Set<String>()
        return ([preferred] + fallbackEndpoints).compactMap { value in
            guard let normalized = try? normalizeEndpoint(value), !seen.contains(normalized) else {
                return nil
            }
            seen.insert(normalized)
            return normalized
        }
    }

    private func remoteImageHost(endpoint: String) async throws -> String {
        if let cached = imgHostCache[endpoint] {
            return cached
        }

        let auth = ApiAuth.current(version: apiVersion, secret: apiSecret)
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
        var components = URLComponents(string: "\(endpoint)/\(path)")
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw APIError.unsupportedEndpoint(endpoint) }

        var lastError: Error?
        for attempt in 0...apiRetryCount {
            do {
                return try await requestAPIValueOnce(url: url, auth: auth)
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

        throw lastError ?? APIError.network("\(url.absoluteString): 请求失败。")
    }

    private func requestAPIValueOnce(url: URL, auth: ApiAuth) async throws -> JSONValue {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(auth.token, forHTTPHeaderField: "token")
        request.setValue(auth.tokenParameter, forHTTPHeaderField: "tokenparam")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, requestName: url.absoluteString)
        let envelope = try decodeEnvelope(data: data, auth: auth, requestName: url.absoluteString)

        guard envelope.code == 200 else {
            throw APIError.api(envelope.errorMessage ?? "接口返回 code \(envelope.code)。")
        }
        guard let data = envelope.data else {
            throw APIError.missingData("接口没有返回 data。")
        }

        if case .string(let encrypted) = data {
            let decrypted = try CryptoBox.aes256ECBDecryptBase64(encrypted, key: auth.token)
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
        case .api, .payload, .unsupportedEndpoint:
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
            throw APIError.decode("\(requestName): \(error.localizedDescription). \(preview)")
        }
    }

    private func validate(response: URLResponse, requestName: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http("\(requestName): HTTP \(http.statusCode)")
        }
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

    private func coverImageURL(imgHost: String?, comicId: String) -> String? {
        guard let imgHost = imgHost?.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/\/+$/, with: ""), !imgHost.isEmpty else {
            return nil
        }
        return "\(imgHost)/media/albums/\(comicId)_3x4.jpg"
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

private struct ApiAuth: Sendable {
    let timestamp: Int
    let token: String
    let tokenParameter: String

    static func current(version: String, secret: String) -> Self {
        let timestamp = Int(Date.now.timeIntervalSince1970)
        return Self(
            timestamp: timestamp,
            token: CryptoBox.md5Hex("\(timestamp)\(secret)"),
            tokenParameter: "\(timestamp),\(version)"
        )
    }
}

enum APIError: LocalizedError {
    case api(String)
    case decode(String)
    case http(String)
    case missingData(String)
    case network(String)
    case payload(String)
    case unsupportedEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .api(let message), .decode(let message), .http(let message), .missingData(let message), .network(let message), .payload(let message):
            message
        case .unsupportedEndpoint(let endpoint):
            "不支持的接口地址：\(endpoint)"
        }
    }
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
