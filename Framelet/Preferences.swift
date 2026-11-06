//
//  Preferences.swift
//  Framelet
//
//  Created by Martin Persson on 2022-12-27.
//

import SwiftUI
import AVFAudio
import AVFoundation
import KeyboardShortcuts
import ScreenCaptureKit
import ServiceManagement

struct Preferences: View {
    static let kFrameRate       = "frameRate"
    static let kHighResolution  = "highRes"
    static let kVideoQuality    = "videoQuality"
    static let kVideoFormat     = "videoFormat"
    static let kEncoder         = "encoder"
    static let kEnableHDR       = "enableHDR"
    static let kShowMouse       = "showMouse"

    static let kAudioFormat     = "audioFormat"
    static let kAudioQuality    = "audioQuality"
    static let kRecordMic       = "recordMic"

    static let kFileName        = "outputFileName"
    static let kSaveDirectory   = "saveDirectory"

    static let kUpdateCheck     = "updateCheck"
    static let kCountdownSecs   = "countDown"
    static let kSystemRecorder  = "useSystemRecorder"
    static let kMergeAudio = "mergeAudioTracks"

    var body: some View {
        VStack {
            TabView {
                GeneralSettings().tabItem {
                    Label("General", systemImage: "gearshape")
                }

                PostprocessingSettings().tabItem {
                    Label("Postprocessing", systemImage: "waveform.badge.plus")
                }

                OutputSettings().tabItem {
                    Label("Destination", systemImage: "folder")
                }

                ShortcutSettings().tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            }
        }.frame(width: 350)
    }

    struct GeneralSettings: View {
        @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
        @State private var loginMessage = ""

        var body: some View {
            VStack(spacing: 0) {
                VideoSettings()
                AudioSettings()
                GroupBox {
                    VStack(alignment: .leading) {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { enabled in
                                do {
                                    if enabled { try SMAppService.mainApp.register() }
                                    else { try SMAppService.mainApp.unregister() }
                                    loginMessage = SMAppService.mainApp.status == .requiresApproval
                                        ? "Approve Framelet in System Settings > General > Login Items." : ""
                                } catch {
                                    loginMessage = error.localizedDescription
                                    launchAtLogin = SMAppService.mainApp.status == .enabled
                                }
                            }
                        if !loginMessage.isEmpty {
                            Text(loginMessage).font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
            }
        }
    }

    struct PostprocessingSettings: View {
        @AppStorage(kMergeAudio) private var mergeAudio = false
        var body: some View {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Merge audio tracks after recording", isOn: $mergeAudio)
                    Text("Mixes system audio and microphone into one track after recording. The original is replaced after the mixed file is checked. Requires FFmpeg.")
                        .font(.footnote).foregroundColor(.secondary)
                }.padding(12)
            }.padding(10)
        }
    }

    struct VideoSettings: View {
        @AppStorage(kFrameRate) private var frameRate: Int = 1
        @AppStorage(kVideoFormat) private var videoFormat: VideoFormat = .mp4
        @AppStorage(kEncoder) private var encoder: Encoder = .h264
        @AppStorage(kShowMouse) private var showMouse: Bool = true

        var body: some View {
            GroupBox {
                Form {
                    Picker("FPS", selection: $frameRate) {
                        Text("1").tag(1)
                        Text("5").tag(5)
                        Text("15").tag(15)
                        Text("30").tag(30)
                    }
                    Picker("Format", selection: $videoFormat) {
                        Text("MP4").tag(VideoFormat.mp4)
                        Text("MOV").tag(VideoFormat.mov)
                    }
                    Picker("Encoder", selection: $encoder) {
                        Text("H.264").tag(Encoder.h264)
                        Text("H.265").tag(Encoder.h265)
                    }
                    Toggle("Show mouse cursor", isOn: $showMouse)
                }.padding(10)
            }.padding(10)
        }
    }

    struct AudioSettings: View {
        @AppStorage(kAudioQuality)   private var audioQuality: AudioQuality = .high
        @AppStorage(kRecordMic)      private var recordMic: Bool = false

        var body: some View {
            GroupBox {
                VStack {
                    Form {
                        Picker("AAC quality", selection: $audioQuality) {
                            Text("Normal - 128 Kbps").tag(AudioQuality.normal)
                            Text("Good - 192 Kbps").tag(AudioQuality.good)
                            Text("High - 256 Kbps").tag(AudioQuality.high)
                            Text("Extreme - 320 Kbps").tag(AudioQuality.extreme)
                        }.padding([.leading, .trailing], 10)
                    }.frame(maxWidth: 250)
                }.padding([.top, .leading, .trailing], 10)
                Spacer(minLength: 5)
                VStack {
                    if #available(macOS 14, *) { // apparently they changed onChange in Sonoma
                        Toggle(isOn: $recordMic) {
                            Text("Record microphone")
                        }.onChange(of: recordMic) {
                            Task { await performMicCheck() }
                        }
                    } else {
                        Toggle(isOn: $recordMic) {
                            Text("Record microphone")
                        }.onChange(of: recordMic) { _ in
                            Task { await performMicCheck() }
                        }
                    }
                    Text("Uses the current input device. Microphone and system audio are saved as separate tracks.")
                        .font(.footnote).foregroundColor(Color.gray)
                }.frame(maxWidth: .infinity).padding(10)
            }.onAppear {
                recordMic = recordMic && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized // untick box if no perms
            }.padding(10)
        }

        func performMicCheck() async {
            guard recordMic == true else { return }
            if await AVCaptureDevice.requestAccess(for: .audio) { return }

            recordMic = false
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Framelet needs permissions!".local
                alert.informativeText = "Framelet needs permission to record your microphone to do this.".local
                alert.addButton(withTitle: "Open Settings".local)
                alert.addButton(withTitle: "No thanks".local)
                alert.alertStyle = .warning
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            }
        }
    }

    struct OutputSettings: View {
        @AppStorage(kFileName)      private var fileName: String = "Recording at %t"
        @AppStorage(kSaveDirectory) private var saveDirectory: String?
        @State private var fileNameLength = 0
        private let dateFormatter = DateFormatter()

        var body: some View {
            VStack {
                GroupBox {
                    VStack {
                        Form {
                            TextField("File name", text: $fileName).frame(maxWidth: 250)
                                .onChange(of: fileName) { newText in
                                    fileNameLength = getFileNameLength(newText)
                                }
                                .onAppear {
                                    dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
                                    fileNameLength = getFileNameLength(fileName)
                                }
                                .foregroundStyle(fileNameLength > NAME_MAX ? .red : .primary)
                        }
                        Text("\"%t\" will be replaced with the recording's start time.")
                            .font(.subheadline).foregroundColor(Color.gray)
                    }.padding(10).frame(maxWidth: .infinity)
                }.padding([.top, .leading, .trailing], 10)
                GroupBox {
                    VStack(spacing: 15) {
                        VStack(spacing: 2) {
                            Button("Select output directory", action: updateOutputDirectory)
                            Text(String(format: "Currently set to \"%@\"".local, (saveDirectory != nil) ? URL(fileURLWithPath: saveDirectory!).lastPathComponent : "an unknown path - please set a new one"))
                                .font(.subheadline).foregroundColor(Color.gray)
                        }
                    }.padding(10).frame(maxWidth: .infinity)
                }.padding([.leading, .trailing, .bottom], 10)
            }.onTapGesture {
                DispatchQueue.main.async { // because the textfield likes focus..
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }
        }

        func getFileNameLength(_ fileName: String) -> Int {
            return fileName.replacingOccurrences(of: "%t", with: dateFormatter.string(from: Date())).count
        }

        func updateOutputDirectory() { // todo: re-sandbox?
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.allowedContentTypes = []
            openPanel.allowsOtherFileTypes = false
            if openPanel.runModal() == NSApplication.ModalResponse.OK {
                saveDirectory = openPanel.urls.first?.path
            }
        }
    }

    struct ShortcutSettings: View {
        var shortcut: [(String, KeyboardShortcuts.Name)] = [
            ("Record focused window".local, .recordCurrentWindow)
        ]
        var body: some View {
            VStack {
                GroupBox {
                    Form {
                        ForEach(shortcut, id: \.1) { shortcut in
                            KeyboardShortcuts.Recorder(shortcut.0, name: shortcut.1).padding([.leading, .trailing], 10).padding(.bottom, 4)
                        }
                    }.frame(alignment: .center).padding([.leading, .trailing], 2).padding(.top, 10).frame(maxWidth: .infinity)
                    Text("Recordings can be stopped with the same shortcut.")
                        .font(.subheadline).foregroundColor(Color.gray).padding(.bottom, 10)
                }.padding(10)
            }
        }
    }

}


extension AppDelegate {
    @objc func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.mainMenu?.items.first?.submenu?.item(at: 2)?.performAction()
        } else if #available(macOS 13, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        for w in NSApplication.shared.windows {
            if w.level.rawValue == 0 || w.level.rawValue == 3 { w.level = .floating }
        }
    }
}

extension NSMenuItem {
    func performAction() {
        guard let menu else {
            return
        }
        menu.performActionForItem(at: menu.index(of: self))
    }
}
