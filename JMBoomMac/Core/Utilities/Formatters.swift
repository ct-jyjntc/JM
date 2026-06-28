import Foundation

enum Formatters {
    static func byteString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func progress(pageIndex: Int, pageCount: Int) -> String {
        guard pageCount > 0 else { return "0 / 0" }
        return "\(pageIndex + 1) / \(pageCount)"
    }
}
