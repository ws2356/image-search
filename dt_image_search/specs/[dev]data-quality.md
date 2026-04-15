For image asset, using the following iOS API to export highest quality modified image:

```swift
let options = PHImageRequestOptions()
options.deliveryMode = .highQualityFormat
options.isNetworkAccessAllowed = false
options.version = .current
PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
    // Check if the resource is in iCloud so no data is returned and handle accordingly
    if let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool, isInCloud {
        // Just ignore for now
        return
    }
    if let data = data {
        // Use the image data (e.g., save to file, upload, etc.)
    }
}
```

For video asset, using the following iOS API to export highest quality modified video:

```swift
func backupVideo(asset: PHAsset) {
    // 1. 获取资源管理
    let manager = PHImageManager.default()
    
    // 2. 判定是否有编辑（通过判定是否存在调整数据）
    asset.requestAdjustmentData(options: nil) { (adjustmentData, info) in
        
        if adjustmentData != nil {
            // --- 路径 A：有编辑，导出编辑后的高质量合成版本 ---
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            manager.requestAVAsset(forVideo: asset, options: options) { (avAsset, audioMix, info) in
                // Check if the resource is in iCloud so no data is returned and handle accordingly
                if let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool, isInCloud {
                    // Just ignore for now
                    return
                }
                guard let avAsset = avAsset else { return }
                exportRenderedVideo(avAsset: avAsset, audioMix: audioMix)
            }
        } else {
            // --- 路径 B：无编辑，直接备份原始文件 (Original) ---
            let resources = PHAssetResource.assetResources(for: asset)
            // 找到视频类型的资源（排除掉 Live Photo 的图片部分）
            if let videoResource = resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo }) {
                let fileURL = getBackupURL(for: videoResource)
                
                PHAssetResourceManager.default().writeData(for: videoResource, toFile: fileURL, options: nil) { error in
                    if error == nil { print("原始文件备份成功") }
                }
            }
        }
    }
}

// 辅助方法：高质量渲染导出
func exportRenderedVideo(avAsset: AVAsset, audioMix: AVAudioMix? = nil) {
    // 使用 HEVC (H.265) 预设可以在保持超高质量的同时减小体积，如果设备不支持会自动回退
    let preset = AVAssetExportPresetHighestQuality 
    guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: preset) else { return }
    
    exportSession.outputURL = getRenderedBackupURL()
    exportSession.outputFileType = .mp4 // 或者 .mov
    exportSession.audioMix = audioMix
    
    exportSession.exportAsynchronously {
        if exportSession.status == .completed {
            print("编辑后的高质量视频导出完成")
        }
    }
}

```