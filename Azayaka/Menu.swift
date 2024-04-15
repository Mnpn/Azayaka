//
//  Menu.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//
import SwiftUI
import ScreenCaptureKit
import ServiceManagement

extension AppDelegate: NSMenuDelegate {
    func createMenu() {
        menu.removeAllItems()
        menu.delegate = self

        if streamType != nil { // recording?
            var typeText = ""
            if screen != nil {
                typeText = "Display ".local + String((availableContent?.displays.firstIndex(where: { $0.displayID == screen?.displayID }))!+1)
            } else if window != nil {
                typeText = window?.owningApplication?.applicationName.uppercased() ?? "A window".local
            } else {
                typeText = "System Audio".local
            }
            menu.addItem(header("Recording ".local + typeText, size: 12))

            menu.addItem(NSMenuItem(title: "Stop Recording".local, action: #selector(stopRecording), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(info)
        } else {
            menu.addItem(header("Audio-only".local))

            let audio = NSMenuItem(title: "System Audio".local, action: #selector(prepRecord), keyEquivalent: "")
            audio.identifier = NSUserInterfaceItemIdentifier(rawValue: "audio")
            menu.addItem(audio)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(header("Displays".local))

            for (i, display) in availableContent!.displays.enumerated() {
                let screenName = NSScreen.screens.first(where: { $0.displayID == display.displayID })?.localizedName ?? "Display ".local + "\(i+1)"
                let displayItem = NSMenuItem(title: "Unknown Display".local, action: #selector(prepRecord), keyEquivalent: "")
                let displayName = screenName + (display.displayID == CGMainDisplayID() ? " (Main)".local : "") + " "
                let displayNameStr = NSMutableAttributedString(string: displayName)
                if let currentDisplayID = getScreenWithMouse()?.displayID {
                    if display.displayID == currentDisplayID {
                        let imageAttachment = NSTextAttachment()
                        imageAttachment.image = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: "current screen".local)
                        let imageString = NSAttributedString(attachment: imageAttachment)
                        displayNameStr.append(imageString)
                    }
                }
                displayItem.attributedTitle = displayNameStr
                displayItem.setAccessibilityLabel(displayName)
                displayItem.title = display.displayID.description
                displayItem.identifier = NSUserInterfaceItemIdentifier(rawValue: "display")
                menu.addItem(displayItem)
            }
            menu.addItem(NSMenuItem.separator())
            menu.addItem(header("Windows".local))

            noneAvailable.isHidden = true
            menu.addItem(noneAvailable)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences…".local, action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Azayaka".local, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateMenu() {
        if streamType != nil { // recording?
            updateIcon()
            info.attributedTitle = NSAttributedString(string: String(format: "Duration: %@\nFile size: %@".local, arguments: [getRecordingLength(), getRecordingSize()]))
        }/* else {
            for window in menu.items.filter({ $0.identifier?.rawValue == "window" }) {
                let matchingWindow = availableContent!.windows.first(where: { window.title == $0.windowID.description })
                guard let matchingWindow else { return }
                let visibleText = getFancyWindowString(window: matchingWindow)
                if window.attributedTitle != visibleText {
                    window.attributedTitle = visibleText
                    window.title = matchingWindow.windowID.description
                }
            }
        }*/
    }

    func refreshWindows(frontOnly: Bool) {
        noneAvailable.isHidden = true
        // in sonoma, there is a new new purple thing overlaying the traffic lights, I don't really want this to show up.
        // its title is simply "Window", but its bundle id is the same as the parent, so this seems like a strange bodge..
        let frontAppId = !frontOnly ? nil : NSWorkspace.shared.frontmostApplication?.processIdentifier 
        let validWindows = availableContent!.windows.filter { 
            guard let app =  $0.owningApplication,
                let title = $0.title, !title.isEmpty else {
                return false
            }
            return !excludedWindows.contains(app.bundleIdentifier)
                && !title.contains("Item-0")
                && title != "Window"
                && (!frontOnly
                    || nil == frontAppId // include all if none is frontmost
                    || (frontAppId! == app.processID))
            }

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
    
    func getAppIcon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            return icon
        }
        return nil
    }
    
    func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) })
        return screenWithMouse
    }

    func newWindow(window: SCWindow) {
        let appName = window.owningApplication?.applicationName ?? "Unknown App".local
        if let item = menu.items.first(where: { $0.attributedTitle?.string.split(separator: "\n").first ?? "" == "￼ " + appName && $0.identifier?.rawValue ?? "" == "application" }) {
            let subMenuItem = NSMenuItem(title: "Unknown".local, action: #selector(prepRecord), keyEquivalent: "")
            subMenuItem.attributedTitle = getFancyWindowString(window: window)
            subMenuItem.title = String(window.windowID)
            subMenuItem.identifier = NSUserInterfaceItemIdentifier("window")
            subMenuItem.setAccessibilityLabel("Window title: ".local + (window.title ?? "No title".local)) // VoiceOver will otherwise read the window ID (the item's non-attributed title)
            item.submenu?.addItem(NSMenuItem.separator())
            item.submenu?.addItem(subMenuItem)
        } else {
            let app = NSMenuItem(title: "Unknown".local, action: nil, keyEquivalent: "")
            app.attributedTitle = getAppNameAttachment(window: window)
            app.identifier = NSUserInterfaceItemIdentifier("application")
            app.setAccessibilityLabel("App name: ".local + appName) // VoiceOver will otherwise read the window ID (the item's non-attributed title)
            let subMenu = NSMenu()
            let subMenuItem = NSMenuItem(title: "Unknown".local, action: #selector(prepRecord), keyEquivalent: "")
            subMenuItem.attributedTitle = getFancyWindowString(window: window)
            subMenuItem.title = String(window.windowID)
            subMenuItem.identifier = NSUserInterfaceItemIdentifier("window")
            subMenuItem.setAccessibilityLabel("Window title: ".local + (window.title ?? "No title".local)) // VoiceOver will otherwise read the window ID (the item's non-attributed title)
            subMenu.addItem(subMenuItem)
            app.submenu = subMenu
            menu.insertItem(app, at: menu.numberOfItems - 4)
        }
        
    }
    
    func getAppNameAttachment(window: SCWindow) -> NSAttributedString {
        let appID = window.owningApplication?.bundleIdentifier ?? "Unknown App".local
        
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = getAppIcon(forBundleIdentifier: appID)
        imageAttachment.bounds = CGRectMake(0, -3, 16, 16)
        let imageString = NSAttributedString(attachment: imageAttachment)
        
        let str = NSMutableAttributedString(string: " " + (window.owningApplication?.applicationName ?? "Unknown App".local))
        let output = NSMutableAttributedString(string: "")
        
        output.append(imageString)
        output.append(str)
        return output
    }

    func getFancyWindowString(window: SCWindow) -> NSAttributedString {
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "window icon".local)
        let imageString = NSAttributedString(attachment: imageAttachment)
        
        let str = NSAttributedString(string: " " + (window.title ?? "No title".local))//, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
        
        let output = NSMutableAttributedString(string: "")
        
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

    func menuWillOpen(_ menu: NSMenu) {
        if streamType == nil { // not recording
            updateAvailableContent(buildMenu: false)
            createMenu()
            //updateMenu()
        }
    }

    func updateIcon() {
        if let button = statusItem.button {
            let iconView = NSHostingView(rootView: MenuBar(recordingStatus: self.streamType != nil, recordingLength: getRecordingLength()))
            iconView.frame = NSRect(x: 0, y: 1, width: self.streamType != nil ? 72 : 33, height: 20)
            button.subviews = [iconView]
            button.frame = iconView.frame
            button.setAccessibilityLabel("Azayaka")
        }
    }
}
