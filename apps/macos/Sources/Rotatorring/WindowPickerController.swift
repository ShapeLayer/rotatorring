import AppKit
import ScreenCaptureKit

/// Lists capturable windows and lets the user pick one to mirror.
final class WindowPickerController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onPick: ((SCWindow) -> Void)?

    private var windows: [SCWindow] = []
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let mirrorButton = NSButton(title: "미러링 시작", target: nil, action: nil)

    /// Bundle ID of the iPhone Mirroring app; preselected when present.
    private static let iPhoneMirroringBundleID = "com.apple.ScreenContinuity"

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "미러링할 창 선택"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 260)
        super.init(window: window)
        buildUI()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let appColumn = NSTableColumn(identifier: .init("app"))
        appColumn.title = "앱"
        appColumn.width = 180
        let titleColumn = NSTableColumn(identifier: .init("title"))
        titleColumn.title = "창 제목"
        titleColumn.width = 240
        let sizeColumn = NSTableColumn(identifier: .init("size"))
        sizeColumn.title = "크기"
        sizeColumn.width = 90
        [appColumn, titleColumn, sizeColumn].forEach(tableView.addTableColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .inset
        tableView.target = self
        tableView.doubleAction = #selector(mirrorSelected(_:))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let refresh = NSButton(title: "새로고침", target: self, action: #selector(refresh(_:)))
        mirrorButton.target = self
        mirrorButton.action = #selector(mirrorSelected(_:))
        mirrorButton.keyEquivalent = "\r"
        mirrorButton.isEnabled = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bar = NSStackView(views: [statusLabel, refresh, mirrorButton])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scroll)
        contentView.addSubview(bar)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bar.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    func reload() {
        statusLabel.stringValue = "창 목록을 불러오는 중…"
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let ownPID = ProcessInfo.processInfo.processIdentifier
                windows = content.windows
                    .filter { window in
                        window.windowLayer == 0
                            && window.frame.width >= 50 && window.frame.height >= 50
                            && window.owningApplication != nil
                            && window.owningApplication?.processID != ownPID
                    }
                    .sorted { lhs, rhs in
                        let l = lhs.owningApplication?.applicationName ?? "", r = rhs.owningApplication?.applicationName ?? ""
                        return l == r ? (lhs.title ?? "") < (rhs.title ?? "") : l.localizedStandardCompare(r) == .orderedAscending
                    }
                tableView.reloadData()
                statusLabel.stringValue = "창 \(windows.count)개"

                let preferred = windows.firstIndex { $0.owningApplication?.bundleIdentifier == Self.iPhoneMirroringBundleID }
                if let row = preferred ?? (windows.isEmpty ? nil : 0) {
                    tableView.selectRowIndexes([row], byExtendingSelection: false)
                    tableView.scrollRowToVisible(row)
                }
                updateButton()
            } catch {
                windows = []
                tableView.reloadData()
                updateButton()
                statusLabel.stringValue = "화면 기록 권한이 필요합니다."
                showPermissionAlert(error)
            }
        }
    }

    private func showPermissionAlert(_ error: Error) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "화면 기록 권한이 필요합니다"
        alert.informativeText = "시스템 설정 › 개인정보 보호 및 보안 › 화면 및 시스템 오디오 기록에서 이 앱을 허용한 뒤 앱을 다시 실행하세요.\n\n(\(error.localizedDescription))"
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "닫기")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn,
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            else { return }
            NSWorkspace.shared.open(url)
        }
    }

    private func updateButton() {
        mirrorButton.isEnabled = windows.indices.contains(tableView.selectedRow)
    }

    @objc private func refresh(_ sender: Any?) { reload() }

    @objc private func mirrorSelected(_ sender: Any?) {
        let row = tableView.selectedRow
        guard windows.indices.contains(row) else { return }
        onPick?(windows[row])
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { windows.count }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButton() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let window = windows[row]
        let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: column.identifier, withImage: column.identifier.rawValue == "app")

        switch column.identifier.rawValue {
        case "app":
            let app = window.owningApplication
            cell.textField?.stringValue = app?.applicationName ?? "?"
            cell.imageView?.image = app.flatMap { NSRunningApplication(processIdentifier: $0.processID)?.icon }
        case "title":
            cell.textField?.stringValue = window.title ?? ""
        default:
            cell.textField?.stringValue = "\(Int(window.frame.width))×\(Int(window.frame.height))"
        }
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier, withImage: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text

        var constraints = [
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
        ]
        if withImage {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            constraints += [
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 18),
                image.heightAnchor.constraint(equalToConstant: 18),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            ]
        } else {
            constraints.append(text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
        }
        NSLayoutConstraint.activate(constraints)
        return cell
    }
}
