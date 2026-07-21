import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    /// 将 loadInPlaceFileRepresentation 包装为 async 函数
    func loadInPlaceFileRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> (URL, Bool) {
        // 使用 withCheckedThrowingContinuation 来桥接回调和 async
        try await withCheckedThrowingContinuation { continuation in
            _ = self.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isInPlace, error in
                if let error = error {
                    // 如果有错误，调用 resume(throwing:)
                    continuation.resume(throwing: error)
                } else if let url = url {
                    // 如果成功获取到 URL，调用 resume(returning:)
                    // 注意：如果是 in-place 文件，后续读取可能需要配合 NSFileCoordinator 或 startAccessingSecurityScopedResource()
                    continuation.resume(returning: (url, isInPlace))
                } else {
                    // 兜底处理：既没错误也没 URL 的罕见情况
                    let unknownError = NSError(domain: "NSItemProviderError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"])
                    continuation.resume(throwing: unknownError)
                }
            }
        }
    }

    func loadFileRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            _ = self.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url)
                } else {
                    let unknownError = NSError(domain: "NSItemProviderError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"])
                    continuation.resume(throwing: unknownError)
                }
            }
        }
    }
}