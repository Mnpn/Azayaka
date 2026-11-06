//
//  Menu.swift
//  Framelet
//
//  Created by Martin Persson on 2022-12-26.
//
import SwiftUI
import ScreenCaptureKit
import ServiceManagement
import KeyboardShortcuts

extension AppDelegate: NSMenuDelegate {
    func createMenu() {
        menu.removeAllItems()
        menu.delegate = self

        if streamType != nil { // recording?
            var typeText = ""
            if screen != nil {
                let fallbackName = String(format: "Display %lld".local, (availableContent?.displays.firstIndex(where: { $0.displayID == screen?.displayID }) ?? -1)+1)
                typeText = NSScreen.screens.first(where: { $0.displayID == screen?.displayID })?.localizedName ?? fallbackName
            } else if window != nil {
                typeText = window?.owningApplication?.applicationName.uppercased() ?? "A window".local
            } else {
                typeText = "System Audio".local
            }
            menu.addItem(header(String(format: "Recording %@".local, typeText), size: 12))

            menu.addItem(NSMenuItem(title: "Stop Recording".local, action: #selector(stopRecordingFromMenu(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(info)

            // while recording, keep a timer which updates the menu's stats
            updateTimer?.invalidate()
            updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.updateMenu()
            }
            RunLoop.current.add(updateTimer!, forMode: .common) // required to have the menu update while open
            updateTimer?.fire()
        } else {
            menu.addItem(header("Windows".local))

            noneAvailable.isHidden = true
            menu.addItem(noneAvailable)
        }

        addMenuFooter(toMenu: menu)
        statusItem.menu = menu
    }

    func updateMenu() {
        if streamType != nil { // recording?
            updateIcon()
            info.attributedTitle = NSAttributedString(string: String(format: "Duration: %@\nFile size: %@".local, arguments: [getRecordingLength(), getRecordingSize()]))
        }
    }

    func refreshWindows() {
        guard streamType == nil else { return }
        for item in menu.items.filter({ $0.identifier?.rawValue == "window" }) {
            menu.removeItem(item)
        }
        let windows = focusedApplicationPID().map { getValidWindows(for: $0) } ?? []
        noneAvailable.isHidden = !windows.isEmpty
        for window in windows {
            let item = NSMenuItem(title: "Unknown".local, action: #selector(prepRecord), keyEquivalent: "")
            item.attributedTitle = getFancyWindowString(window: window)
            item.title = String(window.windowID)
            item.identifier = NSUserInterfaceItemIdentifier("window")
            item.setAccessibilityLabel(String(format: "Window title: %@".local, window.title ?? "No title".local))
            let index = menu.index(of: noneAvailable)
            if index >= 0 { menu.insertItem(item, at: index) }
        }
    }

    func getFancyWindowString(window: SCWindow) -> NSAttributedString {
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "window icon".local)
        let imageString = NSAttributedString(attachment: imageAttachment)

        let str = NSAttributedString(string: " " + (window.title ?? "No title".local))//, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])

        let output = NSMutableAttributedString()
        output.append(imageString)
        output.append(str)
        return output
    }

    func header(_ title: String, size: CGFloat = 10) -> NSMenuItem {
        let headerItem: NSMenuItem
        if #available(macOS 14.0, *) {
            headerItem = NSMenuItem.sectionHeader(title: title.uppercased())
        } else {
            headerItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            headerItem.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: [.font: NSFont.systemFont(ofSize: size, weight: .heavy)])
        }
        return headerItem
    }

    func addMenuFooter(toMenu menu: NSMenu) {
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences…".local, action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Framelet".local, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) {
        allowShortcuts(false) // as per documentation - https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/NSMenuItem%2B%2B.swift#L47
        if streamType == nil { // not recording
            createMenu()
            refreshWindows()
            Task { await updateAvailableContent(buildMenu: false) }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if !isStopping && !isStarting { allowShortcuts(true) }
    }

    func updateIcon() {
        if let button = statusItem.button {
            let iconView = NSHostingView(rootView: MenuBar(recordingStatus: self.streamType != nil, recordingLength: getRecordingLength()))
            iconView.frame = NSRect(x: 0, y: 1, width: self.streamType != nil ? 72 : 33, height: 20)
            button.subviews = [iconView]
            button.frame = iconView.frame
            button.setAccessibilityLabel("Framelet")
        }
    }

}

class NSMenuItemWithIcon: NSMenuItem {
    init(icon: String, title: String, action: Selector?, keyEquivalent: String = "") {
        super.init(title: title, action: action, keyEquivalent: keyEquivalent)
        let attr = NSMutableAttributedString()
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) // todo: consider a11y?
        attr.append(NSAttributedString(attachment: imageAttachment))
        attr.append(NSAttributedString(string: " \(title)"))
        self.attributedTitle = attr
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not a thing")
    }
}
