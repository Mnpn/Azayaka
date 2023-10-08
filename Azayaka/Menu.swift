//
//  Menu.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import ScreenCaptureKit

extension AppDelegate: NSMenuDelegate {
    func createMenu() {
        menu.removeAllItems()
        menu.delegate = self

        if streamType != nil { // recording?
            var typeText = ""
            if screen != nil {
                typeText = "Display " + String((availableContent?.displays.firstIndex(where: { $0.displayID == screen?.displayID }))!+1)
            } else if window != nil {
                typeText = window?.owningApplication?.applicationName.uppercased() ?? "A window"
            } else {
                typeText = "System Audio"
            }
            menu.addItem(header("Recording " + typeText, size: 12))

            menu.addItem(NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: ""))
            menu.addItem(info)
        } else {
            menu.addItem(header("Audio-only"))

            let audio = NSMenuItem(title: "System Audio", action: #selector(prepRecord), keyEquivalent: "")
            audio.identifier = NSUserInterfaceItemIdentifier(rawValue: "audio")
            menu.addItem(audio)

            menu.addItem(header("Displays"))

            for (i, display) in availableContent!.displays.enumerated() {
                let displayItem = NSMenuItem(title: "Unknown Display", action: #selector(prepRecord), keyEquivalent: "")
                displayItem.attributedTitle = NSAttributedString(string: "Display \(i+1)" + (display.displayID == CGMainDisplayID() ? " (Main)" : ""))
                displayItem.title = display.displayID.description
                displayItem.identifier = NSUserInterfaceItemIdentifier(rawValue: "display")
                menu.addItem(displayItem)
            }

            menu.addItem(header("Windows"))

            noneAvailable.isHidden = true
            menu.addItem(noneAvailable)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Azayaka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateMenu() {
        if streamType != nil { // recording?
            info.attributedTitle = NSAttributedString(string: "Duration: \(getRecordingLength())\nFile size: \(getRecordingSize())")
        } else {
            for window in menu.items.filter({ $0.identifier?.rawValue == "window" }) {
                let matchingWindow = availableContent!.windows.first(where: { window.title == $0.windowID.description })
                guard let matchingWindow else { return }
                let visibleText = getFancyWindowString(window: matchingWindow)
                if window.attributedTitle != visibleText {
                    window.attributedTitle = visibleText
                    window.title = matchingWindow.windowID.description
                }
            }
        }
    }

    func refreshWindows() {
        noneAvailable.isHidden = true
        // in sonoma, there is a new new purple thing overlaying the traffic lights, I don't really want this to show up.
        // its title is simply "Window", but its bundle id is the same as the parent, so this seems like a strange bodge..
        let validWindows = availableContent!.windows.filter { !excludedWindows.contains($0.owningApplication!.bundleIdentifier) && !$0.title!.contains("Item-0") && !$0.title!.isEmpty && $0.title != "Window" }

        let programIDs = validWindows.compactMap { $0.windowID.description }
        for window in menu.items.filter({ !programIDs.contains($0.title) && $0.identifier?.rawValue == "window" }) {
            menu.removeItem(window)
        }

        if validWindows.isEmpty {
            noneAvailable.isHidden = false
            return // nothing to add if no windows exist, so why bother
        }

        // add valid windows which are not yet in the list
        let addedItems = menu.items.compactMap { $0.identifier?.rawValue == "window" ? $0.title : "" }
        for window in validWindows.filter({ !addedItems.contains($0.windowID.description) }) {
            newWindow(window: window)
        }
    }

    func newWindow(window: SCWindow) {
        let win = NSMenuItem(title: "Unknown", action: #selector(prepRecord), keyEquivalent: "")
        win.attributedTitle = getFancyWindowString(window: window)
        win.title = String(window.windowID)
        win.identifier = NSUserInterfaceItemIdentifier("window")
        menu.insertItem(win, at: menu.numberOfItems - 3)
    }

    func getFancyWindowString(window: SCWindow) -> NSAttributedString {
        let str = NSMutableAttributedString(string: (window.owningApplication?.applicationName ?? "Unknown App") + "\n")
        str.append(NSAttributedString(string: window.title ?? "No title",
                                      attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .regular),
                                                   .foregroundColor: NSColor.secondaryLabelColor]))
        return str
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

    func menuWillOpen(_ menu: NSMenu) {
        if streamType == nil { // not recording
            updateAvailableContent(buildMenu: false)
            updateMenu()
        }
    }

    func updateIcon() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: self.streamType != nil ? "record.circle.fill" : "record.circle", accessibilityDescription: "Azayaka")
        }
    }
}
