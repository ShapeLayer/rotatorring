import AppKit
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var picker: WindowPickerController?
    private var settings: SettingsWindowController?
    private var mirrors: [MirrorWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        showPicker(nil)
        if !SettingsWindowController.allGranted { showSettings(nil) }
        NSApp.activate()
    }

    @objc func showSettings(_ sender: Any?) {
        if settings == nil { settings = SettingsWindowController() }
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showPicker(nil) }
        return true
    }

    @objc func showPicker(_ sender: Any?) {
        if picker == nil {
            let picker = WindowPickerController()
            picker.onPick = { [weak self] window in self?.openMirror(for: window) }
            self.picker = picker
        }
        picker?.showWindow(nil)
        picker?.window?.makeKeyAndOrderFront(nil)
        picker?.reload()
    }

    private func openMirror(for window: SCWindow) {
        let mirror = MirrorWindowController(target: window)
        mirror.onClose = { [weak self] closed in self?.mirrors.removeAll { $0 === closed } }
        mirrors.append(mirror)
        mirror.start()
        picker?.close()
    }
}
