//
//  InstantShareContext.swift
//  ISFromMobile
//
//  Shared state struct used across TCA features via @Shared / @SharedReader.
//  Replaces InstantShareService's state ownership (sessionId, targetDevice,
//  sharedItems, isLoadingSharedItems).
//
import ComposableArchitecture
import Foundation

struct InstantShareContext: Equatable {
    var sessionId: String = UUID().uuidString.lowercased()
    var targetDevice: InstantShareDiscoveredPC? = nil
    var sharedItems: SharedItems = .text("")
    var isLoadingSharedItems: Bool = false
}

enum SharedItems: Equatable {
    case text(String)
    case images([SharedImage])
    case files([SharedFile])

    var payloadClass: String {
        switch self {
        case .text: return InstantSharePayloadClass.text.rawValue
        case .images: return InstantSharePayloadClass.image.rawValue
        case .files: return InstantSharePayloadClass.text.rawValue
        }
    }

    var targetIntent: String {
        switch self {
        case .text, .files: return "clipboard_only"
        case .images: return "clipboard_or_file"
        }
    }
}

struct SharedImage: Equatable {
    let fileURL: URL
    let filename: String
    let contentType: String
}

struct SharedFile: Equatable {
    let fileURL: URL
    let filename: String
    let contentType: String
}

extension SharedReaderKey where Self == InMemoryKey<InstantShareContext>.Default {
    static var instantShareContext: Self {
        Self[.inMemory("instantShareContext"), default: InstantShareContext()]
    }
}
