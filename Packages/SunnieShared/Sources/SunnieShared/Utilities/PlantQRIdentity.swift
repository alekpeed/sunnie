import Foundation

/// The QR code on a plant's label (PLANT_CARE.md §11).
///
/// **The payload resolves to a plant, and carries nothing else.** A printed label
/// is a public object — it sits on a shelf, a house-sitter photographs it, a
/// visitor scans it out of curiosity. Encoding a nickname or a note into it would
/// put private content on a sticker. What it holds is an opaque token that means
/// nothing to anyone without this app and this device's data.
///
/// The token is per-plant and stable, so a label printed once keeps working, and
/// re-keying a plant is a deliberate act that invalidates the old label.
public enum PlantQRIdentity {

    /// URL host used by scanned codes. Distinct from `plant`, because a scanned
    /// label resolves through the token rather than through a plant ID — the ID
    /// is not what is printed.
    public static let host = "tag"

    /// Tokens are 32 lowercase hex characters. Long enough not to collide, short
    /// enough that the printed code stays coarse and scans from across a room.
    public static let tokenLength = 32

    public static func makeToken(using random: any RandomSource = SystemRandomSource()) -> String {
        let alphabet = Array("0123456789abcdef")
        return String((0..<tokenLength).map { _ in
            alphabet[random.nextIndex(upperBound: alphabet.count)]
        })
    }

    /// A token is well formed if it is the right length and all hex. Checked
    /// before a lookup so a scanned QR code from some other app is rejected
    /// cheaply rather than becoming a storage query.
    public static func isWellFormed(_ token: String) -> Bool {
        token.count == tokenLength
            && token.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// The string encoded into the printed QR code.
    public static func payload(token: String) -> String {
        "\(DeepLinkScheme.scheme)://\(host)/\(token)"
    }

    /// Extracts the token from a scanned string.
    ///
    /// Returns nil for anything that is not one of our labels — a URL from
    /// another app, a Wi-Fi code, a product barcode. Scanning something
    /// unrecognised does nothing, which is better than guessing.
    public static func token(fromScanned scanned: String) -> String? {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)

        // A bare token is accepted too, so a label printed by a future version
        // that omits the URL wrapper still resolves.
        if isWellFormed(trimmed) { return trimmed }

        guard
            let url = URL(string: trimmed),
            url.scheme?.lowercased() == DeepLinkScheme.scheme,
            url.host?.lowercased() == host
        else { return nil }

        let token = url.pathComponents
            .filter { $0 != "/" }
            .first?
            .lowercased()

        guard let token, isWellFormed(token) else { return nil }
        return token
    }
}

/// The app's URL scheme, in one place so the deep-link parser and the QR payload
/// cannot drift apart.
public enum DeepLinkScheme {
    public static let scheme = "sunniedays"
}
