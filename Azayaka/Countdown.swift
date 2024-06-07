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

    @MainActor
    func showCountdown(_ countdown: Int) async {
        if countdown == 0 { return }
        await withCheckedContinuation { continuation in
            self.countdown = countdown
            countdownWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                styleMask: [.borderless],
                backing: .buffered, defer: false)
            countdownWindow?.isReleasedWhenClosed = false
            countdownWindow?.level = .floating
            countdownWindow?.center()
            countdownWindow?.backgroundColor = .clear
            countdownWindow?.isOpaque = false
            countdownWindow?.hasShadow = true
            let countdownView = NSHostingView(rootView: CountdownView().environmentObject(self))
            countdownWindow?.contentView = countdownView
            if let countdownWindow = countdownWindow { countdownWindow.makeKeyAndOrderFront(nil) }
            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + 1, repeating: 1.0)
            timer.setEventHandler {
                Task { @MainActor in
                    self.countdown -= 1
                    if self.countdown < 1 {
                        timer.cancel()
                        self.countdownWindow?.close()
                        self.countdownWindow = nil
                        continuation.resume()
                    }
                }
            }
            timer.resume()
        }
    }
}

struct CountdownView: View {
    @EnvironmentObject var countdownManager: CountdownManager

    var body: some View {
        Text("\(countdownManager.countdown)")
            .font(.largeTitle)
            .foregroundColor(.white)
            .frame(width: 100, height: 100)
            .background(Color.black.opacity(0.7))
            .cornerRadius(10)
            .shadow(radius: 10)
    }
}
