//
//  Menu.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import Foundation
import AppKit
import ScreenCaptureKit

extension AppDelegate {
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
            title.attributedTitle = NSMutableAttributedString(string: "RECORDING " + typeText, attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 12, weight: .heavy), .paragraphStyle: centreText])
            menu.addItem(title)
            menu.addItem(NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: ""))
            menu.addItem(info)
        } else {
            title.attributedTitle = NSAttributedString(string: "SELECT CONTENT TO RECORD", attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 12, weight: .heavy), .paragraphStyle: centreText])
            menu.addItem(title)

            let audio = NSMenuItem(title: "System Audio", action: #selector(prepRecord), keyEquivalent: "")
            audio.identifier = NSUserInterfaceItemIdentifier(rawValue: "audio")
            menu.addItem(audio)

            menu.addItem(NSMenuItem.separator())

            let displays = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
            displays.attributedTitle = NSAttributedString(string: "DISPLAYS", attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 10, weight: .heavy)])
            menu.addItem(displays)

            for (i, display) in availableContent!.displays.enumerated() {
                let displayItem = NSMenuItem(title: "Placeholder", action: #selector(prepRecord), keyEquivalent: "")
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
            Task { await refreshWindows() } // have to refresh here to be able to come back from recording state
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")) // todo: should this really be doable while recording too?
        menu.addItem(NSMenuItem(title: "Quit Azayaka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateMenu() {
        // check duration here so we don't do it in the poor stream on every sample
        if screen == nil && window == nil {
            duration = Double(audioFile?.length ?? 0) / (audioFile?.fileFormat.sampleRate ?? 1) // やばい
        }
        info.attributedTitle = NSAttributedString(string: "Duration: \(getRecordingLength())\nFile size: 0MB")
    }

    func refreshWindows() async {
        noneAvailable.isHidden = true
        let validWindows = availableContent!.windows.filter { !excludedWindows.contains($0.owningApplication!.bundleIdentifier) && !$0.title!.contains("Item-0") && $0.title! != "" }

        let programIDs = validWindows.compactMap { $0.windowID.description }
        for window in menu.items.filter({ !programIDs.contains($0.title) && $0.identifier?.rawValue == "window" }) {
            menu.removeItem(window)
        }
        usleep(10000) // -sigh- sometimes the menu can add/remove so fast that the text doesn't update until a hover. somehow this fixes that.
        if validWindows.count == 0 {
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
        let win = NSMenuItem(title: "Placeholder", action: #selector(prepRecord), keyEquivalent: "")
        win.attributedTitle = NSAttributedString(string: window.owningApplication!.applicationName + ": " + window.title!) // todo: only show title if there are several windows
        win.title = String(window.windowID)
        win.identifier = NSUserInterfaceItemIdentifier("window")
        menu.insertItem(win, at: menu.numberOfItems - 3)
    }

    func updateIcon() {
        if let button = statusItem.button {
            DispatchQueue.main.async {
                button.image = NSImage(systemSymbolName: self.isRecording ? "record.circle.fill" : "record.circle", accessibilityDescription: "Azayaka")
            }
        }
    }
}
