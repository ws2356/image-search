// Purpose: Read build-time metadata (git revision, etc.) from BuildMetadata.json
//          embedded in the app bundle.
// Author: opencode/hy3-free
// Date: 2026-07-16

import Foundation

extension Bundle {
    /// Dictionary of build metadata loaded from `BuildMetadata.json` in this bundle, or `nil` if absent/malformed.
    func buildMetadata() -> [String: String]? {
        guard let url = url(forResource: "BuildMetadata", withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return raw
    }

    /// The 40-char git revision baked into the bundle, or `nil` if not present.
    func gitRevision() -> String? {
        return buildMetadata()?["GitRevision"]
    }
}
