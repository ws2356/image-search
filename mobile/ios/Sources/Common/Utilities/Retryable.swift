//
//  Retryable.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/27.
//

public protocol RetryableError: Error {
    var isRetryable: Bool { get }
}

// 通过扩展 Error，让所有未显式实现该协议的错误默认返回 false
extension Error {
    public var isRetryable: Bool {
        // 如果错误本身实现了 RetryableError，就用它的逻辑，否则默认不重试
        (self as? RetryableError)?.isRetryable ?? false
    }
}

public struct Retryable {
    /// 支持 iOS 15+ 的指数退避重试函数
    /// - Parameters:
    ///   - maxTimes: 最大尝试次数
    ///   - initialDelayNanoseconds: 初始延迟（纳秒），默认 1 秒 (1_000_000_000)
    public static func withRetry<T>(
        maxTimes: Int,
        initialDelayNanoseconds: UInt64 = 1_000_000_000,
        operation: () async throws -> T
    ) async throws -> T {
        let maxAttempts = max(1, maxTimes)
        var currentDelay = initialDelayNanoseconds
        
        for attempt in 1...maxAttempts {
            // 1. 进循环先检查取消
            try Task.checkCancellation()
            
            do {
                return try await operation()
            } catch {
                // 2. 核心改进：如果是由于取消导致的错误，或者 Task 已经被取消，立刻抛出，拒绝盲目重试
                if error is CancellationError || Task.isCancelled {
                    throw error
                }
                
                if !error.isRetryable {
                    throw error
                }
                
                // 3. 如果是最后一次普通业务失败，直接抛出
                if attempt == maxAttempts {
                    throw error
                }
                
                // 4. iOS 15 兼容的睡眠方案：
                // 既然 iOS 15 的 Task.sleep 不会因为取消而中断，我们在睡眠前后都迅速拦截
                try await Task.sleep(nanoseconds: currentDelay)
                
                if Task.isCancelled {
                    throw CancellationError()
                }
                
                // 指数退避
                currentDelay *= 2
            }
        }
        
        throw CancellationError() // 兜底
    }
}
