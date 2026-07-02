//
//  NWEndpoint+Utils.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/3.
//

import Network

extension NWEndpoint.Host {
    /// 转换为纯净的字符串形式（完美剔除 IPv4/IPv6 的 %en0 等本地作用域后缀）
    public var cleanString: String? {
        switch self {
        case .ipv4(let ipv4Address):
            // 声明一个 C 语言风格的缓冲区
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            // 拿到 IPv4 的 4 字节二进制数据
            var rawAddress = ipv4Address.rawValue
            
            // 使用标准的系统函数将二进制转换为纯净 IP 字符串
            _ = inet_ntop(AF_INET, &rawAddress, &buffer, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buffer)
            
        case .ipv6(let ipv6Address):
            // IPv6 的缓冲区需要更大一些
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            var rawAddress = ipv6Address.rawValue
            
            // 关键：inet_ntop 只对纯粹的 IP 二进制进行转换，绝对不会夹带 %en0 网卡后缀
            _ = inet_ntop(AF_INET6, &rawAddress, &buffer, socklen_t(INET6_ADDRSTRLEN))
            return String(cString: buffer)
            
        case .name(let hostname, _):
            // 如果是域名形式（例如 "SongdeMacBook-Pro.local."）
            return hostname
            
        @unknown default:
            // 兼容未来可能增加的其他类型
            return nil
        }
    }
}
