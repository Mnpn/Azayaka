//
//  Preferences.swift
//  Azayaka
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
    static let kHideSelf        = "hideSelf"
    static let kFrontApp        = "frontAppOnly"
    static let kShowMouse       = "showMouse"

    static let kAudioFormat     = "audioFormat"
    static let kAudioQuality    = "audioQuality"
    static let kRecordMic       = "recordMic"

    static let kFileName        = "outputFileName"
    static let kSaveDirectory   = "saveDirectory"
    static let kAutoClipboard   = "autoCopyToClipboard"

    static let kUpdateCheck     = "updateCheck"
    static let kCountdownSecs   = "countDown"
    static let kSystemRecorder  = "useSystemRecorder"

    var body: some View {
        VStack {
            TabView {
                VideoSettings().tabItem {
                    Label("Video", systemImage: "rectangle.inset.filled.badge.record")
                }

                AudioSettings().tabItem {
                    Label("Audio", systemImage: "waveform")
                }

                OutputSettings().tabItem {
                    Label("Destination", systemImage: "folder")
                }

                ShortcutSettings().tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

                OtherSettings().tabItem {
                    Label("Other", systemImage: "gearshape")
                }
            }
        }.frame(width: 350)
    }

    struct VideoSettings: View {
        @AppStorage(kFrameRate)         private var frameRate: Int = 60
        @AppStorage(kHighResolution)    private var highRes: Bool = true
        @AppStorage(kVideoQuality)      private var videoQuality: Double = 1.0
        @AppStorage(kVideoFormat)       private var videoFormat: VideoFormat = .mp4
        @AppStorage(kEncoder)           private var encoder: Encoder = .h264
        @AppStorage(kEnableHDR)         private var enableHDR: Bool = true
        @AppStorage(kHideSelf)          private var hideSelf: Bool = false
        @AppStorage(kFrontApp)          private var frontApp: Bool = false
        @AppStorage(kShowMouse)         private var showMouse: Bool = true

        @AppStorage(kSystemRecorder)    private var useSystemRecorder: Bool = false
        @State private var hoveringWarning: Bool = false

        var body: some View {
            GroupBox {
                Form {
                    Picker("FPS", selection: $frameRate) {
                        Text("60").tag(60)
                        Text("30").tag(30)
                        Text("25").tag(25)
                        Text("24").tag(24)
                        Text("15").tag(15)
                    }.padding(.trailing, 25)
                    Picker("Resolution", selection: $highRes) {
                        Text("Auto").tag(true)
                        Text("Low (1x)").tag(false)
                    }.padding(.trailing, 25)
                    if !useSystemRecorder {
                        Picker("Quality", selection: $videoQuality) {
                            Text("Low").tag(0.3)
                            Text("Medium").tag(0.7)
                            Text("High").tag(1.0)
                        }.padding(.trailing, 25)
                    }
                    Picker("Format", selection: $videoFormat) {
                        Text("MOV").tag(VideoFormat.mov)
                        Text("MP4").tag(VideoFormat.mp4)
                    }.padding(.trailing, 25)
                    HStack {
                        let codec = encoder == .h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc
                        let encoderName = encoder == .h264 ? "H.264" : "H.265"
                        Picker("Encoder", selection: $encoder) {
                            Text("H.264").tag(Encoder.h264)
                            Text("H.265").tag(Encoder.h265)
                        }.padding(.trailing, useSystemRecorder && !deviceSupportsNonKoraiEncoder(codec) ? 0 : 25)
                        if #available(macOS 15, *), useSystemRecorder && !deviceSupportsNonKoraiEncoder(codec) {
                            // This is truly awful.
                            // For some reason my Intel Mac does not show H.265 as an available video codec when using SCRecordingOutputConfiguration.
                            // I don't know why. Apple's sample code and demos show both H.264 and H.265 as available. I guess it might be the same as
                            // with HDR, where Intel just throws a configuration error because it's not supported.
                            // Warning the user if the same is likely to happen on their device is the best UI I could come up with. Alternatively you
                            // could only list available ones (e.g. ["H.264", "H.264 (Legacy)", "H.265 (Legacy)"]), but I don't want to break UserDefaults/tags
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .help(Text(String(format: "It appears that your device might not support %@ with Apple's recorder. You may have to switch back to the default recorder, found in the \"Other\" tab, to use %@.".local, encoderName, encoderName)))
                        }
                    }
                }.frame(maxWidth: 200).padding(10).padding(.leading, 30)
                VStack(alignment: .leading) {
                    // apparently HDR requires Apple Silicon -- https://github.com/xamarin/xamarin-macios/wiki/ScreenCaptureKit-macOS-xcode16.0-b1/89fe4157b4a46303192fa11d3db775baf0c9a543
                    // will throw an invalid configuration error when attempted on intel
                    if #available(macOS 15, *), utsname.isAppleSilicon {
                        Toggle(isOn: $enableHDR) {
                            Text("Record in HDR")
                        }
                    } else {
                        Toggle(isOn: .constant(false)) {
                            Text("Record in HDR")
                        }.disabled(true)
                        Text("Requires Apple Silicon running macOS Sequoia or newer.")
                            .font(.footnote).foregroundColor(Color.gray)
                    }
                    Toggle(isOn: $hideSelf) {
                        Text("Exclude Azayaka itself")
                    }
                    Toggle(isOn: $frontApp) {
                        Text("Only list focused app's windows")
                    }
                    Toggle(isOn: $showMouse) {
                        Text("Show mouse cursor")
                    }
                }.frame(maxWidth: .infinity).padding([.leading, .trailing, .bottom], 10)
            }.padding(10)
        }

        func deviceSupportsNonKoraiEncoder(_ encoder: AVVideoCodecType) -> Bool {
            if #available(macOS 15, *) {
                return SCRecordingOutputConfiguration().availableVideoCodecTypes.contains(encoder)
            }
            return false
        }
    }

    struct AudioSettings: View {
        @AppStorage(kAudioFormat)    private var audioFormat: AudioFormat = .aac
        @AppStorage(kAudioQuality)   private var audioQuality: AudioQuality = .high
        @AppStorage(kRecordMic)      private var recordMic: Bool = false
        @AppStorage(kSystemRecorder) private var usingSystemRecorder: Bool = false

        var body: some View {
            GroupBox {
                VStack {
                    Form {
                        let isLossless = audioFormat == .alac || audioFormat == .flac
                        Picker("Format", selection: $audioFormat) {
                            Text("AAC").tag(AudioFormat.aac)
                            Text("ALAC (Lossless)").tag(AudioFormat.alac)
                            Text("FLAC (Lossless)").tag(AudioFormat.flac)
                            Text("Opus").tag(AudioFormat.opus)
                        }.padding([.leading, .trailing], 10)
                        Picker("Quality", selection: $audioQuality) {
                            if isLossless {
                                Text("Lossless").tag(audioQuality)
                            }
                            Text("Normal - 128Kbps").tag(AudioQuality.normal)
                            Text("Good - 192Kbps").tag(AudioQuality.good)
                            Text("High - 256Kbps").tag(AudioQuality.high)
                            Text("Extreme - 320Kbps").tag(AudioQuality.extreme)
                        }.padding([.leading, .trailing], 10).disabled(isLossless)
                    }.frame(maxWidth: 250)
                    Text(usingSystemRecorder
                         ? "When using the system recorder, these settings only apply to audio-only recordings. Screen recordings will always be 128Kbps AAC."
                         : "These settings are also used when recording video. If set to Opus, MP4 will fall back to AAC.")
                        .font(.footnote).foregroundColor(Color.gray)
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
                    Text("Doesn't apply to system audio-only recordings. Uses the currently set input device. When not using the system recorder, this will be written as a separate audio track.")
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
                alert.messageText = "Azayaka needs permissions!".local
                alert.informativeText = "Azayaka needs permission to record your microphone to do this.".local
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
        @AppStorage(kAutoClipboard) private var autoClipboard: Bool = false
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
                        VStack {
                            Toggle(isOn: $autoClipboard) {
                                Text("Automatically copy recordings to clipboard")
                            }
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
            ("Record system audio".local, .recordSystemAudio),
            ("Record current display".local, .recordCurrentDisplay),
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
    
    struct OtherSettings: View {
        @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
        @AppStorage(kUpdateCheck)    private var updateCheck: Bool = true
        @AppStorage(kCountdownSecs)  private var countDown: Int = 0
        @AppStorage(kSystemRecorder) private var useSystemRecorder: Bool = false

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimum = 0
            formatter.maximum = 99
            return formatter
        }

        var body: some View {
            VStack {
                GroupBox {
                    VStack(alignment: .leading) {
                        Toggle(isOn: $launchAtLogin) {
                            Text("Launch at login")
                        }.onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error.localizedDescription)")
                            }
                        }
                        Toggle(isOn: $updateCheck) {
                            Text("Check for updates at launch")
                        }
                    }.padding([.top, .leading, .trailing], 10).frame(width: 250)
                    Text("Azayaka will check [GitHub](https://github.com/Mnpn/Azayaka/releases) for new updates.")
                        .font(.footnote).foregroundColor(Color.gray).frame(maxWidth: .infinity).padding([.bottom, .leading, .trailing], 10)
                }.padding([.top, .leading, .trailing], 10)
                GroupBox {
                    VStack {
                        Form {
                            TextField("Countdown", value: $countDown, formatter: numberFormatter)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding([.leading, .trailing], 10)
                        }.frame(maxWidth: 200)
                        Text("Countdown to start recording, in seconds.")
                            .font(.subheadline).foregroundColor(Color.gray)
                    }.padding(10).frame(maxWidth: .infinity)
                }.padding([.leading, .trailing], 10)
                GroupBox {
                    if #available(macOS 15, *) {
                        VStack(alignment: .leading) {
                            Toggle(isOn: $useSystemRecorder) {
                                Text("Use system recorder")
                            }
                        }.padding([.top, .leading, .trailing], 10)
                        Text("Since macOS Sequoia, Azayaka can use Apple's provided recorder instead of its own. Try it if Azayaka's recorder has issues for you.\n- It has a fixed audio quality of 128Kbps AAC.\n- Audio-only recordings will always use Azayaka's recorder regardless of this setting.")
                            .font(.footnote).foregroundColor(Color.gray).frame(maxWidth: .infinity).padding([.bottom, .leading, .trailing], 10)
                    } else {
                        VStack(alignment: .leading) {
                            Toggle(isOn: .constant(false)) {
                                Text("Use system recorder")
                            }.disabled(true)
                        }.padding([.top, .leading, .trailing], 10)
                        Text("Using Apple's recorder instead of Azayaka's own requires macOS Sequoia or newer.")
                            .font(.footnote).foregroundColor(Color.gray).frame(maxWidth: .infinity).padding([.bottom, .leading, .trailing], 10)
                    }
                }.padding([.leading, .trailing], 10)
                HStack {
                    Text("Azayaka \(getVersion()) (\(getBuild()))").foregroundColor(Color.secondary)
                    Spacer()
                    Text("https://mnpn.dev")
                }.padding(12).background { VisualEffectView() }.frame(height: 42)
            }
        }

        func getVersion() -> String {
            return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown".local
        }

        func getBuild() -> String {
            return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown".local
        }
    }

    struct VisualEffectView: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView { return NSVisualEffectView() }
        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
    }
}

#Preview {
    Preferences()
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
