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
        let centreText = NSMutableParagraphStyle()
        centreText.alignment = .center

        let title = NSMenuItem(title: "Title", action: nil, keyEquivalent: "")
        if isRecording {
            var typeText = ""
            if screen != nil {
                typeText = "DISPLAY " + String((availableContent?.displays.firstIndex(where: { $0.displayID == screen?.displayID }))!+1)
            } else if window != nil {
                typeText = window?.owningApplication?.applicationName.uppercased() ?? "A WINDOW"
            } else {
                typeText = "SYSTEM AUDIO"
            }
            title.attributedTitle = NSMutableAttributedString(string: "RECORDING " + typeText, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .heavy), .paragraphStyle: centreText])
            menu.addItem(title)
            menu.addItem(NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: ""))
            menu.addItem(info)
        } else {
            title.attributedTitle = NSAttributedString(string: "SELECT CONTENT TO RECORD", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .heavy), .paragraphStyle: centreText])
            menu.addItem(title)

            let audio = NSMenuItem(title: "System Audio", action: #selector(prepRecord), keyEquivalent: "")
            audio.identifier = NSUserInterfaceItemIdentifier(rawValue: "audio")
            menu.addItem(audio)

            let displays = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
            displays.attributedTitle = NSAttributedString(string: "DISPLAYS", attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .heavy)])
            menu.addItem(displays)

            for (i, display) in availableContent!.displays.enumerated() {
                let displayItem = NSMenuItem(title: "Mondai", action: #selector(prepRecord), keyEquivalent: "")
                displayItem.attributedTitle = NSAttributedString(string: "Display \(i+1)" + (display.displayID == CGMainDisplayID() ? " (Main)" : ""))
                displayItem.title = display.displayID.description
                displayItem.identifier = NSUserInterfaceItemIdentifier(rawValue: "display")
                menu.addItem(displayItem)
            }

            let windows = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
            windows.attributedTitle = NSAttributedString(string: "WINDOWS", attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 10, weight: .heavy)])
            menu.addItem(windows)
            noneAvailable.isHidden = true
            menu.addItem(noneAvailable)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Azayaka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateMenu() {
        if isRecording {
            // check duration here so we don't do it in the poor stream on every sample
            if screen == nil && window == nil {
                duration = Double(audioFile?.length ?? 0) / (audioFile?.fileFormat.sampleRate ?? 1)
            }
            info.attributedTitle = NSAttributedString(string: "Duration: \(getRecordingLength())\nFile size: \(getRecordingSize())")
        } else {
            for window in menu.items.filter({ $0.identifier?.rawValue == "window" }) {
                let matchingWindow = availableContent!.windows.first(where: { window.title == $0.windowID.description })!
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
        let validWindows = availableContent!.windows.filter { !excludedWindows.contains($0.owningApplication!.bundleIdentifier) && !$0.title!.contains("Item-0") && !$0.title!.isEmpty }

        let programIDs = validWindows.compactMap { $0.windowID.description }
        for window in menu.items.filter({ !programIDs.contains($0.title) && $0.identifier?.rawValue == "window" }) {
            menu.removeItem(window)
        }
        usleep(10000) // -sigh- sometimes the menu can add/remove so fast that the text doesn't update until a hover. somehow this fixes that.
        if validWindows.isEmpty {
            noneAvailable.isHidden = false
            sleep(2) // WTF?
            return // nothing to add if no windows exist, so why bother
        }

        // add valid windows which are not yet in the list
        let addedItems = menu.items.compactMap { $0.identifier?.rawValue == "window" ? $0.title : "" }
        for window in validWindows.filter({ !addedItems.contains($0.windowID.description) }) {
            newWindow(window: window)
        }
    }

    func newWindow(window: SCWindow) {
        let win = NSMenuItem(title: "Mondai", action: #selector(prepRecord), keyEquivalent: "")
        win.attributedTitle = getFancyWindowString(window: window)
        win.title = String(window.windowID)
        win.identifier = NSUserInterfaceItemIdentifier("window")
        menu.insertItem(win, at: menu.numberOfItems - 3)
    }

    func getFancyWindowString(window: SCWindow) -> NSAttributedString {
        let str = NSMutableAttributedString(string: (window.owningApplication?.applicationName ?? "Mondai") + "\n")
        str.append(NSAttributedString(string: window.title ?? "Motto Marutto Mondai",
                                      attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .regular),
                                                   .foregroundColor: NSColor.secondaryLabelColor]))
        return str
    }

    func menuWillOpen(_ menu: NSMenu) {
        if !isRecording {
            updateAvailableContent(buildMenu: false)
            updateTimer?.invalidate()
            updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                self.updateMenu()
            }
            RunLoop.current.add(updateTimer!, forMode: .common)
        }
    }

    func updateIcon() {
        if let button = statusItem.button {
            DispatchQueue.main.async {
                button.image = NSImage(systemSymbolName: self.isRecording ? "record.circle.fill" : "record.circle", accessibilityDescription: "Azayaka")
            }
        }
    }
}
