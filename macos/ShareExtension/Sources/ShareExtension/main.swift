import Foundation

// The system loads the Share Extension via `NSExtensionMain` (resolved from
// `NSExtensionPrincipalClass` in Info.plist). The top-level code below is
// required by SwiftPM's `executableTarget` linker contract; it provides the
// missing `_ShareExtension_main` entry point symbol and delegates to
// `NSExtensionMain`, which never returns until the extension finishes.
@_silgen_name("NSExtensionMain")
private func NSExtensionMain(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>
) -> Int32

exit(NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv))
