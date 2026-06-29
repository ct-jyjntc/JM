import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ReaderService {
    static let shared = ReaderService(api: .shared)

    private let defaultShunt = "1"
    private let seedMap: [UInt32] = [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
    private let api: JMBoomAPI
    private var manifestCache: [String: ReaderManifest] = [:]

    init(api: JMBoomAPI) {
        self.api = api
    }

    func manifest(readId: String, endpoint: String, shunt: String?) async throws -> ReaderManifest {
        let readId = readId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !readId.isEmpty else { throw APIError.missingData("阅读章节 ID 为空。") }

        let shunt = normalizedShunt(shunt)
        let key = "\(endpoint)|\(readId)|\(shunt)"
        if let cached = manifestCache[key] {
            return cached
        }

        let result = try await api.fetchReaderHTML(readId: readId, endpoint: endpoint, shunt: shunt)
        let manifest = try parseManifest(endpoint: result.endpoint, readId: readId, shunt: shunt, html: result.html)
        manifestCache[key] = manifest
        return manifest
    }

    func materializedPage(readId: String, index: Int, endpoint: String, shunt: String?, cacheLimitBytes: UInt64) async throws -> MaterializedReaderPage {
        let manifest = try await manifest(readId: readId, endpoint: endpoint, shunt: shunt)
        guard manifest.pages.indices.contains(index) else {
            throw APIError.missingData("阅读页超出范围。")
        }

        let page = manifest.pages[index]
        let cacheURL = try pageCacheURL(manifest: manifest, page: page)

        if FileManager.default.fileExists(atPath: cacheURL.path),
           let dimensions = imageDimensions(url: cacheURL) {
            return MaterializedReaderPage(readId: manifest.readId, index: index, fileURL: cacheURL, width: dimensions.width, height: dimensions.height, isCached: true)
        }

        let bytes = try await api.downloadImageBytes(page.sourceURL, referer: manifest.endpoint)
        let dimensions = try writeCache(bytes: bytes, manifest: manifest, page: page, cacheURL: cacheURL, cacheLimitBytes: cacheLimitBytes)

        return MaterializedReaderPage(readId: manifest.readId, index: index, fileURL: cacheURL, width: dimensions.width, height: dimensions.height, isCached: false)
    }

    func prefetch(readId: String, centerIndex: Int, radius: Int, endpoint: String, shunt: String?, cacheLimitBytes: UInt64) async {
        guard radius > 0, let manifest = try? await manifest(readId: readId, endpoint: endpoint, shunt: shunt), !manifest.pages.isEmpty else {
            return
        }

        let start = max(0, centerIndex - radius)
        let end = min(manifest.pages.count - 1, centerIndex + radius)
        for index in start...end where index != centerIndex {
            _ = try? await materializedPage(readId: readId, index: index, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes)
        }
    }

    func cacheStats(cacheLimitBytes: UInt64) throws -> ReaderCacheStats {
        let files = try cacheFiles()
        let total = files.reduce(UInt64(0)) { $0 + $1.size }
        return ReaderCacheStats(cacheDirectory: try cacheRoot(), totalBytes: total, fileCount: files.count, cacheLimitBytes: cacheLimitBytes, trimBytes: trimBytes(cacheLimitBytes))
    }

    func clearCache(cacheLimitBytes: UInt64) throws -> ReaderCacheStats {
        let root = try cacheRoot()
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        manifestCache = [:]
        return try cacheStats(cacheLimitBytes: cacheLimitBytes)
    }

    private func parseManifest(endpoint: String, readId: String, shunt: String, html: String) throws -> ReaderManifest {
        let resultObject = try captureObject(pattern: #"(?s)const\s+result\s*=\s*(\{.*?\});"#, html: html, name: "result")
        let configObject = try captureObject(pattern: #"(?s)const\s+config\s*=\s*(\{.*?\});"#, html: html, name: "config")
        let images = try captureStringArray(key: "images", script: resultObject)
        let rawImgHost = try captureScriptString(key: "imghost", script: configObject)
        let rawJmid = try captureScriptString(key: "jmid", script: configObject)
        let cache = try captureScriptString(key: "cache", script: configObject)

        guard !images.isEmpty else {
            throw APIError.missingData("阅读信息没有页面图片。这个章节可能暂时不可读，或当前线路没有返回图片列表。")
        }
        let imgHost = rawImgHost.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/\/+$/, with: "")
        let jmid = rawJmid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !imgHost.isEmpty, !jmid.isEmpty else {
            throw APIError.missingData("阅读信息缺少图片主机或 jmid。")
        }

        let pages = images.enumerated().compactMap { index, image -> ReaderPage? in
            let imageName = image.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !imageName.isEmpty else {
                return nil
            }
            return URL(string: "\(imgHost)/media/photos/\(jmid)/\(imageName)\(cache)").map {
                ReaderPage(index: index, pageName: pageName(from: imageName), sourceURL: $0)
            }
        }
        guard !pages.isEmpty else {
            throw APIError.missingData("阅读图片列表为空。")
        }

        return ReaderManifest(
            endpoint: endpoint,
            readId: readId,
            readIdNumber: UInt32(readId) ?? captureUInt(pattern: #"var\s+aid\s*=\s*(\d+);"#, html: html) ?? 0,
            shunt: shunt,
            scrambleId: captureUInt(pattern: #"var\s+scramble_id\s*=\s*(\d+);"#, html: html) ?? 220_980,
            speed: captureString(pattern: #"var\s+speed\s*=\s*'([^']*)';"#, html: html) ?? "",
            pages: pages
        )
    }

    private func captureObject(pattern: String, html: String, name: String) throws -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            throw APIError.missingData("阅读页面没有包含 \(name) 脚本。")
        }
        return String(html[range])
    }

    private func captureStringArray(key: String, script: String) throws -> [String] {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"(?s)\b\#(escapedKey)\s*:\s*\[(.*?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
              let range = Range(match.range(at: 1), in: script) else {
            throw APIError.payload("阅读脚本缺少 \(key) 列表。")
        }

        let arrayBody = String(script[range])
        let stringPattern = #""((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'"#
        guard let stringRegex = try? NSRegularExpression(pattern: stringPattern) else {
            throw APIError.payload("阅读脚本字符串解析器初始化失败。")
        }

        return stringRegex.matches(in: arrayBody, range: NSRange(arrayBody.startIndex..., in: arrayBody)).compactMap { match in
            let doubleRange = Range(match.range(at: 1), in: arrayBody)
            let singleRange = Range(match.range(at: 2), in: arrayBody)
            let raw = doubleRange.map { String(arrayBody[$0]) } ?? singleRange.map { String(arrayBody[$0]) }
            return raw.map(unescapeJavaScriptString)
        }
    }

    private func captureScriptString(key: String, script: String) throws -> String {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"\b\#(escapedKey)\s*:\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)) else {
            throw APIError.payload("阅读脚本缺少 \(key)。")
        }

        let doubleRange = Range(match.range(at: 1), in: script)
        let singleRange = Range(match.range(at: 2), in: script)
        guard let raw = doubleRange.map({ String(script[$0]) }) ?? singleRange.map({ String(script[$0]) }) else {
            return ""
        }

        return unescapeJavaScriptString(raw)
    }

    private func captureUInt(pattern: String, html: String) -> UInt32? {
        captureString(pattern: pattern, html: html).flatMap(UInt32.init)
    }

    private func captureString(pattern: String, html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }

    private func writeCache(bytes: Data, manifest: ReaderManifest, page: ReaderPage, cacheURL: URL, cacheLimitBytes: UInt64) throws -> (width: Double, height: Double) {
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if shouldDecode(manifest: manifest, page: page) {
            guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw APIError.decode("图片解码失败。")
            }
            let decoded = try decodeScrambledImage(image: image, readId: manifest.readIdNumber, pageName: page.pageName)
            guard let destination = CGImageDestinationCreateWithURL(cacheURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw APIError.decode("无法创建图片缓存。")
            }
            CGImageDestinationAddImage(destination, decoded, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw APIError.decode("写入图片缓存失败。")
            }
            try cleanupCache(limitBytes: cacheLimitBytes)
            return (Double(decoded.width), Double(decoded.height))
        }

        try bytes.write(to: cacheURL, options: .atomic)
        try cleanupCache(limitBytes: cacheLimitBytes)
        return imageDimensions(url: cacheURL) ?? (1, 1)
    }

    private func decodeScrambledImage(image: CGImage, readId: UInt32, pageName: String) throws -> CGImage {
        let width = image.width
        let height = image.height
        let seed = Int(calculateSeed(readId: readId, pageName: pageName))
        let remainder = height % seed
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw APIError.decode("无法创建图片画布。")
        }

        for index in 0..<seed {
            var segmentHeight = height / seed
            var destinationY = segmentHeight * index
            let sourceY = height - segmentHeight * (index + 1) - remainder

            if index == 0 {
                segmentHeight += remainder
            } else {
                destinationY += remainder
            }

            guard let segment = image.cropping(to: CGRect(x: 0, y: sourceY, width: width, height: segmentHeight)) else {
                continue
            }

            context.draw(segment, in: CGRect(x: 0, y: height - destinationY - segmentHeight, width: width, height: segmentHeight))
        }

        guard let decoded = context.makeImage() else {
            throw APIError.decode("无法生成还原后的图片。")
        }
        return decoded
    }

    private func shouldDecode(manifest: ReaderManifest, page: ReaderPage) -> Bool {
        manifest.readIdNumber > 0
            && sourceExtension(page.sourceURL) != "gif"
            && manifest.readIdNumber >= manifest.scrambleId
    }

    private func calculateSeed(readId: UInt32, pageName: String) -> UInt32 {
        if readId < 268_850 {
            return 10
        }

        let key = "\(readId)\(pageName)"
        let md5 = CryptoBox.md5Hex(key)
        var charCode = Int(md5.utf8.last ?? 0)
        let left: UInt32 = 268_850
        let right: UInt32 = 421_925

        if (left...right).contains(readId) {
            charCode %= 10
        } else if readId >= right + 1 {
            charCode %= 8
        }

        return seedMap.indices.contains(charCode) ? seedMap[charCode] : 10
    }

    private func pageCacheURL(manifest: ReaderManifest, page: ReaderPage) throws -> URL {
        let ext = shouldDecode(manifest: manifest, page: page) ? "png" : sourceExtension(page.sourceURL)
        return try cacheRoot()
            .appending(path: safePathSegment(manifest.readId), directoryHint: .isDirectory)
            .appending(path: String(format: "%04d.%@", page.index + 1, ext))
    }

    private func cacheRoot() throws -> URL {
        try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "JMBoomMac/reader", directoryHint: .isDirectory)
    }

    private func cleanupCache(limitBytes: UInt64) throws {
        let files = try cacheFiles()
        let total = files.reduce(UInt64(0)) { $0 + $1.size }
        guard total > limitBytes else { return }

        var current = total
        let target = trimBytes(limitBytes)
        for file in files.sorted(by: { $0.modified < $1.modified }) {
            if current <= target { break }
            try? FileManager.default.removeItem(at: file.url)
            current = current > file.size ? current - file.size : 0
        }
    }

    private func cacheFiles() throws -> [CacheFile] {
        let root = try cacheRoot()
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return CacheFile(url: url, size: UInt64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast)
        }
    }

    private func trimBytes(_ limitBytes: UInt64) -> UInt64 {
        limitBytes * 82 / 100
    }

    private func imageDimensions(url: URL) -> (width: Double, height: Double)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double else {
            return nil
        }
        return (width, height)
    }

    private func normalizedShunt(_ shunt: String?) -> String {
        let value = shunt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultShunt : value
    }

    private func pageName(from image: String) -> String {
        let withoutQuery = image.split(separator: "?").first.map(String.init) ?? image
        let fileName = withoutQuery.split(separator: "/").last.map(String.init) ?? withoutQuery
        return fileName.split(separator: ".").dropLast().joined(separator: ".")
    }

    private func unescapeJavaScriptString(_ value: String) -> String {
        var result = ""
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]
            guard character == "\\" else {
                result.append(character)
                index = value.index(after: index)
                continue
            }

            let nextIndex = value.index(after: index)
            guard nextIndex < value.endIndex else {
                result.append(character)
                index = nextIndex
                continue
            }

            let escaped = value[nextIndex]
            switch escaped {
            case "\\", "\"", "'", "/":
                result.append(escaped)
                index = value.index(after: nextIndex)
            case "b":
                result.append("\u{08}")
                index = value.index(after: nextIndex)
            case "f":
                result.append("\u{0C}")
                index = value.index(after: nextIndex)
            case "n":
                result.append("\n")
                index = value.index(after: nextIndex)
            case "r":
                result.append("\r")
                index = value.index(after: nextIndex)
            case "t":
                result.append("\t")
                index = value.index(after: nextIndex)
            case "u":
                let hexStart = value.index(after: nextIndex)
                guard let hexEnd = value.index(hexStart, offsetBy: 4, limitedBy: value.endIndex) else {
                    result.append(escaped)
                    index = value.index(after: nextIndex)
                    continue
                }

                let hex = String(value[hexStart..<hexEnd])
                if let scalarValue = UInt32(hex, radix: 16), let scalar = UnicodeScalar(scalarValue) {
                    result.append(Character(scalar))
                    index = hexEnd
                } else {
                    result.append(escaped)
                    index = value.index(after: nextIndex)
                }
            default:
                result.append(escaped)
                index = value.index(after: nextIndex)
            }
        }

        return result
    }

    private func sourceExtension(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "gif": "gif"
        case "png": "png"
        case "webp": "webp"
        case "jpeg": "jpg"
        case "jpg": "jpg"
        default: "jpg"
        }
    }

    private func safePathSegment(_ value: String) -> String {
        let filtered = value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return filtered.isEmpty ? "unknown" : String(filtered)
    }

    private struct CacheFile {
        let url: URL
        let size: UInt64
        let modified: Date
    }
}

struct ReaderCacheStats: Sendable {
    let cacheDirectory: URL
    let totalBytes: UInt64
    let fileCount: Int
    let cacheLimitBytes: UInt64
    let trimBytes: UInt64
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
}
