import AppKit
import ServiceManagement
import SwiftUI

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Tuck Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()  // Tuck is an accessory app; without this the window opens behind the frontmost app
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @AppStorage("hoverDelay") private var delay = 1.8
    @AppStorage("SUEnableAutomaticChecks") private var checkForUpdates = true  // Sparkle's own keys
    @AppStorage("SUAutomaticallyUpdate") private var installUpdates = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: $delay, in: 0.2...2.5, step: 0.1)
                        Text("\(delay, format: .number.precision(.fractionLength(1))) s")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch {
                            NSLog("Tuck: login item: \(error)")
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                    .disabled(!isBundled)
            }
            Section("Updates") {
                Toggle("Check GitHub for updates once a day", isOn: $checkForUpdates)
                    .onChange(of: checkForUpdates) { _, v in updater.updater.automaticallyChecksForUpdates = v }
                Toggle("Install updates automatically", isOn: $installUpdates)
                    .onChange(of: installUpdates) { _, v in updater.updater.automaticallyDownloadsUpdates = v }
                    .disabled(!checkForUpdates)
                Button("Check Now") { updater.checkForUpdates(nil) }
            }
            .disabled(!isBundled)
            Section {
                Link("Tuck on GitHub", destination: githubURL)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
