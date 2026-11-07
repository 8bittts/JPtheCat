import Foundation

#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// Chromium / Electron **safeStorage** on macOS (AES-128-CBC, PBKDF2-HMAC-SHA1).
/// Used read-only to decrypt Grok Bot's `sand-secrets.json` token blobs after the login Keychain
/// secret is read through `/usr/bin/security` (same honesty class as `CursorAuthToken`).
enum ChromiumOSCrypt {
	static let salt = Array("saltysalt".utf8)
	static let rounds: UInt32 = 1003
	static let iv = [UInt8](repeating: 0x20, count: 16)

	static func deriveKey(secret: Data) -> [UInt8] {
		#if canImport(CommonCrypto)
		var derived = [UInt8](repeating: 0, count: 16)
		secret.withUnsafeBytes { secretBytes in
			_ = CCKeyDerivationPBKDF(
				CCPBKDFAlgorithm(kCCPBKDF2),
				secretBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
				secretBytes.count,
				salt,
				salt.count,
				CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
				rounds,
				&derived,
				derived.count)
		}
		return derived
		#else
		return []
		#endif
	}

	/// Decrypt a base64 `v10` / `v11` safeStorage blob.
	static func decrypt(key: [UInt8], valueBase64: String) -> Data? {
		#if canImport(CommonCrypto)
		guard let raw = Data(base64Encoded: valueBase64.trimmingCharacters(in: .whitespacesAndNewlines))
		else { return nil }
		let prefix = Data("v10".utf8)
		let prefix11 = Data("v11".utf8)
		let ciphertext: Data
		if raw.starts(with: prefix) {
			ciphertext = raw.dropFirst(prefix.count)
		} else if raw.starts(with: prefix11) {
			ciphertext = raw.dropFirst(prefix11.count)
		} else {
			return nil
		}
		guard key.count == kCCKeySizeAES128 else { return nil }
		return aes128CbcDecrypt(key: key, ciphertext: Data(ciphertext))
		#else
		return nil
		#endif
	}

	#if canImport(CommonCrypto)
	private static func aes128CbcDecrypt(key: [UInt8], ciphertext: Data) -> Data? {
		var out = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
		var outLength = 0
		let status = ciphertext.withUnsafeBytes { ct in
			iv.withUnsafeBytes { ivBytes in
				key.withUnsafeBytes { keyBytes in
					CCCrypt(
						CCOperation(kCCDecrypt),
						CCAlgorithm(kCCAlgorithmAES),
						CCOptions(kCCOptionPKCS7Padding),
						keyBytes.baseAddress, kCCKeySizeAES128,
						ivBytes.baseAddress,
						ct.baseAddress, ciphertext.count,
						&out, out.count,
						&outLength)
				}
			}
		}
		guard status == kCCSuccess else { return nil }
		return Data(out.prefix(outLength))
	}
	#endif
}
