import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        let appName = ProcessInfo.processInfo.processName

        let appMenu = NSMenu(title: appName)
        appMenu.addItem(withTitle: "\(appName) 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "설정…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "\(appName) 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(item("기타 가리기", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(withTitle: "모두 보기", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "\(appName) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, to: main)

        let file = NSMenu(title: "파일")
        file.addItem(withTitle: "새 미러…", action: #selector(AppDelegate.showPicker(_:)), keyEquivalent: "n")
        file.addItem(.separator())
        file.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(file, to: main)

        add(makeTransformMenu(title: "변환"), to: main)

        let view = NSMenu(title: "보기")
        view.addItem(withTitle: "실제 크기 (100%)", action: #selector(MirrorWindowController.actualSize(_:)), keyEquivalent: "0")
        view.addItem(withTitle: "확대", action: #selector(MirrorWindowController.zoomIn(_:)), keyEquivalent: "=")
        view.addItem(withTitle: "축소", action: #selector(MirrorWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(.separator())
        view.addItem(item("원본 창 크기 따라가기", #selector(MirrorWindowController.toggleFollowSource(_:)), "f", [.command, .option]))
        view.addItem(item("항상 위에 표시", #selector(MirrorWindowController.toggleFloating(_:)), "t", [.command, .option]))
        add(view, to: main)

        let window = NSMenu(title: "윈도우")
        window.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        add(window, to: main)
        NSApp.windowsMenu = window

        return main
    }

    /// Rotation/flip items; also used as the mirror view's context menu.
    static func makeTransformMenu(title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.addItem(withTitle: "오른쪽으로 회전", action: #selector(MirrorWindowController.rotateRight(_:)), keyEquivalent: "r")
        menu.addItem(withTitle: "왼쪽으로 회전", action: #selector(MirrorWindowController.rotateLeft(_:)), keyEquivalent: "l")
        menu.addItem(.separator())
        menu.addItem(item("좌우 반전", #selector(MirrorWindowController.flipHorizontal(_:)), "h", [.command, .shift]))
        menu.addItem(item("상하 반전", #selector(MirrorWindowController.flipVertical(_:)), "v", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("원래대로", #selector(MirrorWindowController.resetTransform(_:)), "r", [.command, .shift]))
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String,
                             _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func add(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}
