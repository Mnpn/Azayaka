//
//  Menu.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import Foundation
import AppKit

extension AppDelegate {
    func createMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let centreText = NSMutableParagraphStyle()
        centreText.alignment = .center

        let title = NSMenuItem(title: "Title", action: nil, keyEquivalent: "")
        if isRecording {
            title.attributedTitle = NSAttributedString(string: "RECORDING", attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 12, weight: .heavy), .paragraphStyle: centreText])
            menu.addItem(title)
            menu.addItem(NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: ""))
            // todo: display recording stats such as length and size
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
                let display = NSMenuItem(title: "Display \(i+1)" + (display.displayID == CGMainDisplayID() ? " (Main)" : ""), action: #selector(prepRecord), keyEquivalent: "")
                display.identifier = NSUserInterfaceItemIdentifier(rawValue: "display")
                menu.addItem(display)
            }

            let windows = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
            windows.attributedTitle = NSAttributedString(string: "WINDOWS", attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 10, weight: .heavy)])
            menu.addItem(windows)

            for app in availableContent!.applications.filter({ !excludedWindows.contains($0.bundleIdentifier) }) {
                let window = NSMenuItem(title: "Placeholder", action: #selector(prepRecord), keyEquivalent: "")
                window.attributedTitle = NSAttributedString(string: app.applicationName)
                window.title = app.bundleIdentifier
                menu.addItem(window)
            }
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: nil, keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Azayaka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateIcon() {
        if let button = statusItem.button {
            DispatchQueue.main.async {
                button.image = NSImage(systemSymbolName: self.isRecording ? "record.circle.fill" : "record.circle", accessibilityDescription: "Azayaka")
            }
        }
    }
}
