import AppKit
import ApplicationServices

/// Settings window showing whether the permissions the app needs are granted.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private struct Permission {
        let title: String
        let detail: String
        let settingsURL: String
        let isGranted: () -> Bool
        let request: () -> Void
    }

    static var allGranted: Bool { permissions.allSatisfy { $0.isGranted() } }

    private static let permissions: [Permission] = [
        Permission(
            title: "화면 기록",
            detail: "원본 창을 캡처해서 보여주는 데 필요합니다.",
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            isGranted: { CGPreflightScreenCaptureAccess() },
            request: { _ = CGRequestScreenCaptureAccess() }),
        Permission(
            title: "손쉬운 사용",
            detail: "미러 창의 클릭과 키 입력을 원본 창에 전달하는 데 필요합니다.",
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            isGranted: { AXIsProcessTrusted() },
            request: { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }),
    ]

    private var statusLabels: [NSTextField] = []
    private var requestButtons: [NSButton] = []
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private var refreshTimer: Timer?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "설정 — 권한"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let rows: [NSView] = Self.permissions.enumerated().map { index, permission in
            let title = NSTextField(labelWithString: permission.title)
            title.font = .boldSystemFont(ofSize: 13)
            let detail = NSTextField(wrappingLabelWithString: permission.detail)
            detail.textColor = .secondaryLabelColor
            detail.font = .systemFont(ofSize: 11)
            let text = NSStackView(views: [title, detail])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 2
            text.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let status = NSTextField(labelWithString: "")
            status.font = .systemFont(ofSize: 12, weight: .medium)
            status.alignment = .right
            statusLabels.append(status)

            let request = NSButton(title: "권한 요청", target: self, action: #selector(requestPermission(_:)))
            request.tag = index
            requestButtons.append(request)
            let open = NSButton(title: "설정 열기", target: self, action: #selector(openSettings(_:)))
            open.tag = index

            let row = NSStackView(views: [text, status, request, open])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            return row
        }

        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor

        let relaunch = NSButton(title: "앱 다시 실행", target: self, action: #selector(relaunch(_:)))
        let footer = NSStackView(views: [summaryLabel, relaunch])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: rows + [footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])
        (rows + [footer]).forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refresh()
        // Permissions change in System Settings; keep the display current while the window is open.
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refresh() {
        for (index, permission) in Self.permissions.enumerated() {
            let granted = permission.isGranted()
            statusLabels[index].stringValue = granted ? "✓ 허용됨" : "✕ 허용 안 됨"
            statusLabels[index].textColor = granted ? .systemGreen : .systemRed
            requestButtons[index].isEnabled = !granted
        }
        summaryLabel.stringValue = Self.allGranted
            ? "모든 권한이 허용되었습니다."
            : "시스템 설정에서 허용한 뒤에도 표시가 바뀌지 않으면 앱을 다시 실행하세요. 목록에 이미 있는데 동작하지 않으면 − 로 지우고 다시 추가하세요."
    }

    @objc private func requestPermission(_ sender: NSButton) {
        Self.permissions[sender.tag].request()
        refresh()
    }

    @objc private func openSettings(_ sender: NSButton) {
        guard let url = URL(string: Self.permissions[sender.tag].settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func relaunch(_ sender: Any?) {
        let bundleURL = Bundle.main.bundleURL
        // Launch the new instance only after this one has exited.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"", bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
