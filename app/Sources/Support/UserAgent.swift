import Foundation
import UIKit

/// archive.org fronts downloads with infrastructure that is unfriendly to
/// unknown clients. We present as mobile Safari on the *actual* OS version --
/// an iPhone app claiming to be macOS Safari is internally inconsistent and
/// trips heuristics harder than sending nothing unusual at all.
enum UserAgent {
    static let value: String = {
        let v = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let major = UIDevice.current.systemVersion.split(separator: ".").first.map(String.init) ?? "17"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(v) like Mac OS X) "
             + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major).0 "
             + "Mobile/15E148 Safari/604.1"
    }()

    /// Header set applied to every archive.org request.
    static var headers: [String: String] {
        [
            "User-Agent": value,
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept-Encoding": "identity",   // never let the CDN re-encode the .gz
        ]
    }

    static func configured(_ config: URLSessionConfiguration) -> URLSessionConfiguration {
        config.httpAdditionalHeaders = headers
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 60 * 60   // a 330 MB download on slow cellular
        return config
    }
}
