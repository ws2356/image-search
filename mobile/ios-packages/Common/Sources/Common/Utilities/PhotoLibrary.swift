//
//  PhotoLibrary.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/4/23.
//

#if canImport(UIKit)
import UIKit
import Photos
import PhotosUI

extension PHPhotoLibrary {
    public static func showLimitedPicker(_ completionHandler: @escaping @Sendable ([String]) -> Void) {
        DispatchQueue.main.async {
            // 获取 RootVC 的健壮写法
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first as? UIWindowScene
            guard let rootVC = windowScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                completionHandler([])
                return
            }
            
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootVC) { assetIds in
                DispatchQueue.main.async {
                    completionHandler(assetIds)
                }
            }
        }
    }
}
#endif
