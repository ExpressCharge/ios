//
//  MagicEmailDeepLinkHandler.swift
//  ExpresScan
//
//  Plan B2 — parser for the magic-email customer sign-in deep link
//  (`https://example.com/m/<token>`). Sibling of
//  `RootView.parseUserSignInDeepLink` (the QR-card path) and
//  `parseChargerDeepLink` (the customer charger path).
//
//  The token is opaque to the iOS side — the server verifies it. We
//  only enforce a minimum length + URL-safe alphabet so a crafted /m/
//  URL doesn't cause a wasted POST.
//

import Foundation

public enum MagicEmailDeepLinkHandler {

    /// Returns the trailing token from a magic-email sign-in URL of
    /// the form `https://example.com/m/<token>`. Returns `nil`
    /// when the URL doesn't match the shape we accept.
    ///
    /// Token rules:
    ///   - At least 8 characters
    ///   - URL-safe alphabet only (`A-Z`, `a-z`, `0-9`, `-`, `_`)
    public static func parse(_ url: URL) -> String? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return parse(components)
    }

    /// `URLComponents` overload used by the router's pre-parsed path.
    public static func parse(_ components: URLComponents) -> String? {
        guard
            (components.scheme ?? "").lowercased() == "https",
            components.host == BuildConfig.chargerLinkHost
        else { return nil }
        let prefix = "/m/"
        guard components.path.hasPrefix(prefix) else { return nil }
        let raw = String(components.path.dropFirst(prefix.count))
        return validatedToken(raw)
    }

    /// Validate the token shape. Enforces min length 8 and a
    /// URL-safe alphabet so we reject obvious garbage at the boundary.
    static func validatedToken(_ raw: String) -> String? {
        guard raw.count >= 8 else { return nil }
        let alphabet = CharacterSet(
            charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        )
        return raw.unicodeScalars.allSatisfy { alphabet.contains($0) } ? raw : nil
    }
}
