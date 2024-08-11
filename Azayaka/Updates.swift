//
//  Updates.swift
//  Azayaka
//
//  Created by Martin Persson on 2024-04-15.
//

import Foundation
import AppKit

class Updates {
    private var updateVersion: String?
    private let RELEASE_URL = "https://github.com/Mnpn/Azayaka/releases/tag/v"
    private let GHAPI_RELEASES_URL = "https://api.github.com/repos/Mnpn/Azayaka/releases"
    var updateURL: String {
        RELEASE_URL + updateVersion!
    }

    func createUpdateNotice() -> NSMenuItem? {
        var updateNotice: NSMenuItem? = nil;
        if UserDefaults.standard.bool(forKey: Preferences.kUpdateCheck) &&
            updateVersion != nil && updateVersion != Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            updateNotice = NSMenuItem(title: String(format: "Update to %@…".local, updateVersion!), action: #selector(openUpdatePage), keyEquivalent: "")
        }
        return updateNotice;
    }

    func checkForUpdates() {
        let task = URLSession.shared.dataTask(with: URL(string: GHAPI_RELEASES_URL)!, completionHandler: { [self] (data, response, error) -> Void in
            if error == nil {
                let jsonResponse = data!
                do {
                    let releaseData = try JSONDecoder().decode([FailableDecodable<GHRelease>].self, from: jsonResponse).compactMap { $0.base }
                    updateVersion = String((releaseData.first?.tag_name.dropFirst())!) // "v1.2" -> "1.2"
                } catch { print("update check failed: " + error.localizedDescription); return }
            }
        })
        task.resume()
    }

    @objc private func openUpdatePage() { } // erhm..

    // https://stackoverflow.com/a/46369152
    struct FailableDecodable<Base : Decodable> : Decodable {
        let base: Base?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.base = try? container.decode(Base.self)
        }
    }
}
