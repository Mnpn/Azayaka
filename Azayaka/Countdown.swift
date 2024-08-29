//
//  Countdown.swift
//  Azayaka
//
//  Created by resistanceto on 2024/5/30.
//

import SwiftUI

class CountdownManager: ObservableObject {
    @Published var countdown: Int = 0
    static let shared = CountdownManager()
    private var countdownWindow: NSWindow?
    var timer: DispatchSourceTimer!
    private var continuation: CheckedContinuation<Bool, Never>?

    @MainActor
    func showCountdown(_ countdown: Int) async -> Bool { // returns if the countdown completed
        if countdown == 0 || NSEvent.modifierFlags.contains(NSEvent.ModifierFlags.option) { return true } // todo: can't use option to skip when using a keybind
        return await withCheckedContinuation { cont in
            continuation = cont
            self.countdown = countdown
            countdownWindow = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            countdownWindow?.isReleasedWhenClosed = false
            countdownWindow?.level = .floating
            countdownWindow?.center()
            countdownWindow?.backgroundColor = .clear
            countdownWindow?.isOpaque = false
            countdownWindow?.hasShadow = true
            let countdownView = NSHostingView(rootView: CountdownView().environmentObject(self))
            countdownWindow?.contentView = countdownView
            if let countdownWindow = countdownWindow { countdownWindow.orderFrontRegardless() }
            timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + 1, repeating: 1.0)
            timer.setEventHandler {
                Task { @MainActor in
                    self.countdown -= 1
                    if self.countdown < 1 {
                        self.finishCountdown(startRecording: true)
                    }
                }
            }
            timer.resume()
        }
    }

    @objc func finishCountdown(startRecording: Bool = false) {
        timer.cancel()
        countdownWindow?.close()
        countdownWindow = nil
        timer = nil
        continuation?.resume(returning: startRecording)
    }
}

struct CountdownView: View {
    @EnvironmentObject var countdownManager: CountdownManager
    @State var progress: Double = 0.0
    @State private var hovering = false
    @Environment(\.colorScheme) var theme

    var body: some View {
        ZStack {
            Image(systemName: "chevron.forward.2")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
                .hidden(!hovering)
            Text("\(countdownManager.countdown)")
                .font(.largeTitle)
                .foregroundColor(.primary)
                .hidden(hovering)
            Circle().fill(.gray).opacity(0.25) // because .fill(bool ? a : b) is "only available in macOS 14"
                .scaleEffect(0.7)
                .hidden(!hovering)
            Circle()
                .stroke(.gray, lineWidth: 8)
                .scaleEffect(0.7)
            Circle() // because apparently scaling a ProgressView doesn't work?
                .trim(from: 0, to: progress)
                .rotation(.degrees(-90))
                .stroke(
                    UserDefaults.standard.integer(forKey: "AppleAccentColor") != -1 ? Color.accentColor : // because "graphite" is literally Color.gray (the lower ring)..
                        theme == .dark ? Color.white : Color.black, // ..and this then needs to adapt to the theme
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .scaleEffect(0.7)
                .onAppear {
                    withAnimation(.linear(duration: TimeInterval(countdownManager.countdown))) {
                        progress = 1
                    }
                }
                .onHover { over in // circles have to go above for the hover area to be correct
                    withAnimation(.easeInOut(duration: 0.1)) {
                        hovering = over
                    }
                }
        }
        .background(.regularMaterial)
        .cornerRadius(.infinity)
        .onTapGesture {
            countdownManager.finishCountdown(startRecording: true)
        }
    }
}

// https://stackoverflow.com/a/57420479
extension View {
    func hidden(_ shouldHide: Bool) -> some View {
        opacity(shouldHide ? 0 : 1)
    }
}
