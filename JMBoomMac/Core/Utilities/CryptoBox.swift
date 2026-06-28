import CommonCrypto
import CryptoKit
import Foundation

enum CryptoBox {
    static func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func aes256ECBDecryptBase64(_ value: String, key: String) throws -> String {
        guard let encrypted = Data(base64Encoded: value) else {
            throw CryptoError.invalidBase64
        }

        let keyData = Data(key.utf8)
        let outputCapacity = encrypted.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var outputLength = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            encrypted.withUnsafeBytes { encryptedBytes in
                keyData.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode + kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        kCCKeySizeAES256,
                        nil,
                        encryptedBytes.baseAddress,
                        encrypted.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw CryptoError.decryptFailed(status)
        }

        output.removeSubrange(outputLength..<output.count)

        guard let text = String(data: output, encoding: .utf8) else {
            throw CryptoError.invalidUTF8
        }

        return text
    }

    enum CryptoError: LocalizedError {
        case invalidBase64
        case decryptFailed(CCCryptorStatus)
        case invalidUTF8

        var errorDescription: String? {
            switch self {
            case .invalidBase64: "加密响应不是有效的 Base64。"
            case .decryptFailed(let status): "AES 解密失败：\(status)"
            case .invalidUTF8: "解密后的内容不是 UTF-8 文本。"
            }
        }
    }
}
