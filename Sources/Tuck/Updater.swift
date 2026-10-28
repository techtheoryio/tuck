import Sparkle

/// Sparkle reads `appcast.xml` from the latest GitHub release (SUFeedURL in the Info.plist written by build-app.sh).
/// Bare SwiftPM builds have no Info.plist, so the updater (and the login item) only work inside the bundled .app.
@MainActor let isBundled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil

@MainActor let updater = SPUStandardUpdaterController(
    startingUpdater: isBundled, updaterDelegate: updaterDelegate, userDriverDelegate: nil)

@MainActor private let updaterDelegate = UpdaterDelegate()  // Sparkle holds its delegate weakly

/// Tuck never quits on its own, so Sparkle's default of installing a downloaded update on quit would never happen.
/// Install and relaunch right away instead; to-dos are saved on every change, so nothing is lost.
@MainActor final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        immediateInstallHandler()
        return true
    }
}
