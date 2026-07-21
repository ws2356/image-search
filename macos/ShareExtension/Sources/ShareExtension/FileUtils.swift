import Foundation

struct FileLinker {
    
    enum LinkError: Error {
        case sourceNotExists
        case cannotGetFileInfo
        case linkError(Int32)
    }
    
    /// 优雅地创建硬链接，支持跨分区降级拷贝与可重入
    /// - Parameters:
    ///   - source: 源文件路径
    ///   - destination: 目标文件路径
    static func createHardLinkOrCopy(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        
        // 1. 确保源文件存在
        guard fileManager.fileExists(atPath: source.path) else {
            throw LinkError.sourceNotExists
        }
        
        // 2. 处理“可重入性”：检查目标路径是否已存在
        if fileManager.fileExists(atPath: destination.path) {
            if isSameFile(source, destination) {
                // 已经是同一个文件（硬链接关系），优雅地直接返回成功
                return
            } else {
                // 目标存在但不是当前源文件的硬链接，先将其删除以允许重建
                try? fileManager.removeItem(at: destination)
            }
        }
        
        // 3. 尝试创建硬链接 (使用标准 POSIX 提升性能和准确度)
        let result = link(source.path, destination.path)
        
        if result == 0 {
            // 硬链接创建成功
            return
        }
        
        // 4. 失败处理：检查是否是因为跨分区 (EXDEV)
        let errorNumber = errno
        if errorNumber == EXDEV {
            // 跨磁盘分区，优雅降级为拷贝
            try fileManager.copyItem(at: source, to: destination)
        } else {
            // 其他错误（如权限不足等），抛出异常
            throw LinkError.linkError(errorNumber)
        }
    }
    
    /// 核心辅助方法：通过底层 inode 和 device ID 判断两个 URL 是否指向同一份物理数据
    private static func isSameFile(_ url1: URL, _ url2: URL) -> Bool {
        var stat1 = stat()
        var stat2 = stat()
        
        guard stat(url1.path, &stat1) == 0, stat(url2.path, &stat2) == 0 else {
            return false
        }
        
        // 当且仅当设备号 (st_dev) 和 节点号 (st_ino) 完全一致时，它们才是硬链接关系
        return stat1.st_dev == stat2.st_dev && stat1.st_ino == stat2.st_ino
    }
}