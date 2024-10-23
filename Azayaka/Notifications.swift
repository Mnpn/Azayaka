//
//  Notifications.swift
//  Azayaka
//
//  Created by Martin Persson on 2024-08-07.
//

import AppKit
import UserNotifications

extension AppDelegate: UNUserNotificationCenterDelegate {
    func sendRecordingFinishedNotification() {
        let un = UNUserNotificationCenter.current()
        un.requestAuthorization(options: [.alert]) { [self] (authorised, error) in
            if authorised {
                let autoCopy = ud.bool(forKey: Preferences.kAutoClipboard)
                let content = UNMutableNotificationContent()
                content.title = autoCopy ? "Recording Completed and Copied".local : "Recording Completed".local
                if let filePath = filePath {
                    content.body = String(format: "File saved to: %@".local, filePath)
                    content.userInfo = ["recordingFilePath" : filePath] // if we don't have the file path we should not be attempting to trash anything, so don't even include the userInfo if not

                    // add the "move to trash" action button
                    let trashButton = UNNotificationAction(identifier: "moveRecordingToTrash", title: "Move to Trash".local, options: .destructive)
                    let copyButton = UNNotificationAction(identifier: "copyRecordingToClipboard", title: "Copy to Clipboard".local, options: .destructive)
                    let notificationCategory = UNNotificationCategory(
                        identifier: "recordingFinished",
                        actions: autoCopy ? [trashButton] : [trashButton, copyButton],
                        intentIdentifiers: [])
                    un.setNotificationCategories([notificationCategory])
                } else {
                    content.body = String(format: "File saved to folder: %@".local, ud.string(forKey: Preferences.kSaveDirectory)!)
                }
                content.sound = UNNotificationSound.default
                content.categoryIdentifier = "recordingFinished"
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
                let request = UNNotificationRequest(identifier: "azayaka.completed.\(Date.now)", content: content, trigger: trigger)
                un.add(request) { error in
                    if let error = error { print("Notification failed to send: \(error.localizedDescription)") }
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler:
                                @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        guard let recordingFilePath = (userInfo["recordingFilePath"] as? String) else { completionHandler(); return }

        switch response.actionIdentifier {
            case "moveRecordingToTrash":
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: recordingFilePath), resultingItemURL: nil)
                } catch {
                    print("Attempt at moving recording to trash failed: \(error.localizedDescription)")
                }
                break
            case "copyRecordingToClipboard":
                copyToClipboard([NSURL(fileURLWithPath: recordingFilePath)])
                break
            default: // focus finder and select file
                NSWorkspace.shared.selectFile(URL(fileURLWithPath: recordingFilePath).path, inFileViewerRootedAtPath: "")
                break
        }

        completionHandler()
    }
}
