import CoreGraphics
import SwiftUI
import UIKit
import WebKit
import XCTest

@MainActor
enum SnapshotSupport {
    private static var hostedWindow: UIWindow?
    private static let fileManager = FileManager.default
    private static let minimumBytePrecision = 0.95

    static func assertSnapshot(
        pageName: String,
        viewController: UIViewController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let renderedImage = try renderImage(for: viewController)
        let referenceURL = referenceImageURL(pageName: pageName, file: file)

        if isRecording {
            try persistPNG(renderedImage, to: referenceURL)
            return
        }

        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            let actualURL = try writeFailureArtifact(renderedImage, pageName: pageName, suffix: "actual", file: file)
            XCTFail(
                "Missing reference snapshot at \(referenceURL.path). " +
                    "Run with RECORD_SNAPSHOTS=1 to create it. Rendered image saved to \(actualURL.path).",
                file: file,
                line: line
            )
            return
        }

        let expectedImage = try loadImage(at: referenceURL)
        let expectedPixels = try normalizedPixelData(for: expectedImage)
        let actualPixels = try normalizedPixelData(for: renderedImage)

        let precision = pixelPrecision(expected: expectedPixels, actual: actualPixels)
        guard precision >= minimumBytePrecision else {
            let actualURL = try writeFailureArtifact(renderedImage, pageName: pageName, suffix: "actual", file: file)
            XCTFail(
                "Snapshot mismatch for \(pageName) at byte precision \(String(format: "%.6f", precision)). " +
                    "Expected \(referenceURL.lastPathComponent). " +
                    "Actual render saved to \(actualURL.path).",
                file: file,
                line: line
            )
            return
        }
    }

    static func releaseWindow() {
        hostedWindow?.isHidden = true
        hostedWindow?.rootViewController = nil
        hostedWindow = nil
    }

    static var snapshotLanguage: String {
        return "en-US"
    }

    static var snapshotDeviceDisplayName: String {
        if let deviceAlias = runtimeConfig?.deviceAlias?.trimmingCharacters(in: .whitespacesAndNewlines),
           !deviceAlias.isEmpty {
            return deviceAlias
        }
        if let simulatorName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !simulatorName.isEmpty {
            return simulatorName
        }
        return UIDevice.current.model
    }

    static var isRecording: Bool {
        if let record = runtimeConfig?.record {
            return record
        }
        let value = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    static func fileSafeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let collapsedWhitespace = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        let scalars = collapsedWhitespace.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars).replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func normalizedSnapshotLanguage(_ rawLanguage: String) -> String {
        let normalized = rawLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !normalized.isEmpty else {
            return "en-US"
        }
        if normalized.contains("-") {
            return normalized
        }
        let region = Locale.current.regionCode ?? "US"
        return "\(normalized)-\(region)"
    }

    static func loadLaunchScreenViewController() throws -> UIViewController {
        let bundle = try launchScreenBundle()
        let storyboard = UIStoryboard(name: "LaunchScreen", bundle: bundle)
        guard let viewController = storyboard.instantiateInitialViewController() else {
            throw SnapshotError.missingLaunchScreenController
        }
        return viewController
    }

    private static func renderImage(for viewController: UIViewController) throws -> UIImage {
        releaseWindow()

        let window = makeWindow()
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = viewController
        window.makeKeyAndVisible()

        viewController.view.frame = window.bounds
        viewController.view.backgroundColor = .clear
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        // Wait for any WKWebView to finish loading + a DOM rendering buffer.
        waitForWebViewsToLoad(in: window)

        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)

        // 1. Capture the main-process hierarchy (misses WKWebView content).
        let baseImage = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        // 2. Composite each WKWebView's rendered content via takeSnapshot.
        let webViews = findWebViews(in: window)
        guard !webViews.isEmpty else {
            hostedWindow = window
            return baseImage
        }

        let finalImage = renderer.image { context in
            baseImage.draw(at: .zero)
            for webView in webViews {
                guard let snapshot = takeSnapshotSync(webView) else { continue }
                let frameInWindow = webView.convert(webView.bounds, to: window)
                snapshot.draw(in: frameInWindow)
            }
        }

        hostedWindow = window
        return finalImage
    }

    // MARK: - WKWebView Snapshot Helpers

    /// Waits for all `WKWebView` instances in the window to finish navigation,
    /// then gives the DOM a short buffer to finish rendering.
    private static func waitForWebViewsToLoad(in window: UIWindow, timeout: TimeInterval = 15.0) {
        let webViews = findWebViews(in: window)
        guard !webViews.isEmpty else { return }

        let observer = WebViewLoadObserver(webViews: webViews)
        observer.start()

        let deadline = Date().addingTimeInterval(timeout)
        while !observer.isComplete, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        // DOM rendering buffer after didFinish fires.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }

    private static func findWebViews(in view: UIView) -> [WKWebView] {
        var result: [WKWebView] = []
        if let webView = view as? WKWebView {
            result.append(webView)
        }
        for subview in view.subviews {
            result.append(contentsOf: findWebViews(in: subview))
        }
        return result
    }

    /// Synchronously captures a `WKWebView`'s rendered content via its own API.
    private static func takeSnapshotSync(_ webView: WKWebView) -> UIImage? {
        var result: UIImage?
        let done = XCTestExpectation(description: "takeSnapshot")
        webView.takeSnapshot(with: nil) { image, _ in
            result = image
            done.fulfill()
        }
        _ = XCTWaiter.wait(for: [done], timeout: 10.0)
        return result
    }

    private static func referenceImageURL(pageName: String, file: StaticString) -> URL {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let snapshotsDirectory = testFileURL.deletingLastPathComponent().appendingPathComponent("__Snapshots__", isDirectory: true)
        let filename = [
            pageName,
            fileSafeComponent(snapshotDeviceDisplayName),
            fileSafeComponent(snapshotLanguage),
        ].joined(separator: "_") + ".png"
        return snapshotsDirectory.appendingPathComponent(filename)
    }

    private static func writeFailureArtifact(
        _ image: UIImage,
        pageName: String,
        suffix: String,
        file: StaticString
    ) throws -> URL {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let iosRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let artifactsDirectory = iosRoot
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("snapshot-artifacts", isDirectory: true)
        let filename = [
            pageName,
            fileSafeComponent(snapshotDeviceDisplayName),
            fileSafeComponent(snapshotLanguage),
            suffix,
        ].joined(separator: "_") + ".png"
        let artifactURL = artifactsDirectory.appendingPathComponent(filename)
        try persistPNG(image, to: artifactURL)
        return artifactURL
    }

    private static var runtimeConfig: SnapshotRuntimeConfig? {
        let url = runtimeConfigURL
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SnapshotRuntimeConfig.self, from: data)
    }

    private static var runtimeConfigURL: URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("snapshot-config.json")
    }

    private static func persistPNG(_ image: UIImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let pngData = image.pngData() else {
            throw SnapshotError.failedToEncodePNG
        }
        try pngData.write(to: url)
    }

    private static func loadImage(at url: URL) throws -> UIImage {
        guard let image = UIImage(contentsOfFile: url.path) else {
            throw SnapshotError.failedToLoadReference(url.path)
        }
        return image
    }

    private static func normalizedPixelData(for image: UIImage) throws -> Data {
        guard let cgImage = image.cgImage else {
            throw SnapshotError.failedToAccessCGImage
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(.init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        var data = Data(count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let rendered = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo.rawValue
                  ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard rendered else {
            throw SnapshotError.failedToNormalizePixels
        }

        return data
    }

    private static func pixelPrecision(expected: Data, actual: Data) -> Double {
        guard expected.count == actual.count, !expected.isEmpty else {
            return 0
        }
        let matchingBytes = zip(expected, actual).reduce(into: 0) { count, pair in
            if pair.0 == pair.1 {
                count += 1
            }
        }
        return Double(matchingBytes) / Double(expected.count)
    }

    private static func makeWindow() -> UIWindow {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) {
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            return window
        }

        return UIWindow(frame: UIScreen.main.bounds)
    }

    private static func launchScreenBundle() throws -> Bundle {
        let bundles = Bundle.allBundles + Bundle.allFrameworks
        if let matchingBundle = bundles.first(where: { $0.path(forResource: "LaunchScreen", ofType: "storyboardc") != nil }) {
            return matchingBundle
        }
        throw SnapshotError.missingLaunchScreenBundle
    }
}

/// Observes `WKNavigationDelegate` callbacks on a set of `WKWebView` instances and
/// signals when every web view has finished (or failed) loading its initial content.
@MainActor
private final class WebViewLoadObserver: NSObject, WKNavigationDelegate {
    private let webViews: [WKWebView]
    private var remaining: Int

    var isComplete: Bool { remaining == 0 }

    init(webViews: [WKWebView]) {
        self.webViews = webViews
        self.remaining = webViews.count
        super.init()
    }

    func start() {
        for webView in webViews {
            if !webView.isLoading {
                remaining -= 1
                continue
            }
            webView.navigationDelegate = self
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError _: Error) { finish(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError _: Error) { finish(webView) }

    private func finish(_ webView: WKWebView) {
        webView.navigationDelegate = nil
        remaining -= 1
    }
}

private struct SnapshotRuntimeConfig: Decodable {
    let record: Bool
    let language: String?
    let deviceAlias: String?
}

enum SnapshotError: LocalizedError {
    case missingLaunchScreenBundle
    case missingLaunchScreenController
    case failedToEncodePNG
    case failedToAccessCGImage
    case failedToNormalizePixels
    case failedToLoadReference(String)

    var errorDescription: String? {
        switch self {
        case .missingLaunchScreenBundle:
            return "Could not locate the bundle containing LaunchScreen.storyboard."
        case .missingLaunchScreenController:
            return "LaunchScreen.storyboard is missing an initial view controller."
        case .failedToEncodePNG:
            return "Failed to encode the rendered snapshot as PNG."
        case .failedToAccessCGImage:
            return "Failed to access the rendered snapshot's CGImage."
        case .failedToNormalizePixels:
            return "Failed to normalize rendered snapshot pixels for comparison."
        case let .failedToLoadReference(path):
            return "Failed to load reference snapshot at \(path)."
        }
    }
}

@MainActor
struct SnapshotPageHost<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    pageContent
                }
            } else {
                NavigationView {
                    pageContent
                }
                .navigationViewStyle(.stack)
            }
        }
        .background(backgroundGradient)
    }

    private var pageContent: some View {
        Group {
            if #available(iOS 16.0, *) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarBackground(navigationBarBackground, for: .navigationBar)
                    .toolbarColorScheme(.light, for: .navigationBar)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color.white,
                Color(red: 0.96, green: 1.0, blue: 0.97),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var navigationBarBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color.white,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
