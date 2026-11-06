# Stability and testing

Framelet aims to protect in-progress recordings, but it has not been exhaustively tested across macOS versions, hardware, filesystems, and recording conditions.

- ScreenCaptureKit is asked to stop before the capture queue is drained and the file writer finishes. A success notification is sent after the writer reports completion.
- Movie fragments are configured at a 10-second interval. This can help recovery after an interruption, but it does not guarantee a playable file or bound the amount of data lost.
- The free-space check runs before recording and every five seconds. The 1 GB threshold is not a disk reservation. Other processes can consume space between checks; a disconnected volume or full disk can still interrupt finalization.
- When free space is low or cannot be checked during a recording, Framelet attempts a clean stop and skips optional audio merging. A failed merge retains the original two-track recording. Successful merge validation checks playability, track structure and duration; it is not a full decode or a guarantee of perfect audio.
- The reported sleep/wake reboot has not been diagnosed because a panic report was not available. Framelet requests a stop on sleep, but macOS can sleep before asynchronous finalization is complete. Stop important recordings manually before closing the lid.
- Quit while recording is not yet a controlled asynchronous shutdown.
- The global shortcut, long recordings, microphone and system audio, static slides, window changes, multiple screens, audio merging, force-quit recovery, low-space behavior, and login/sleep cycles should be tested on the target Mac before relying on the app for important work.

The Command Line Tools build uses the macOS 26.5 SDK and a pinned KeyboardShortcuts dependency. SwiftUI compiler plugins required by some newer SDKs may be missing from standalone Command Line Tools.
