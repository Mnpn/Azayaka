import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: apply-finder-icon <app> <icon>\n", stderr)
    exit(2)
}
let appPath = CommandLine.arguments[1]
let iconPath = CommandLine.arguments[2]
guard let icon = NSImage(contentsOfFile: iconPath) else {
    fputs("Could not open icon.\n", stderr)
    exit(1)
}
guard NSWorkspace.shared.setIcon(icon, forFile: appPath, options: []) else {
    fputs("Could not set custom Finder icon.\n", stderr)
    exit(1)
}
print("Applied custom Finder icon.")
