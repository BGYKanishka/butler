import Foundation
import ScreenCaptureKit

if #available(macOS 13.0, *) {
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
        print(content != nil)
    }
}
