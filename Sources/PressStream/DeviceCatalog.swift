import AppKit
import AVFoundation
import ScreenCaptureKit

struct DeviceOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct DisplayOption: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
}

enum DeviceCatalog {
    static func audioInputs() -> [DeviceOption] {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = [.microphone, .external]
        } else {
            types = [.builtInMicrophone, .externalUnknown]
        }
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified)
            .devices.map { DeviceOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func cameras() -> [DeviceOption] {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = [.builtInWideAngleCamera, .external, .continuityCamera]
        } else {
            types = [.builtInWideAngleCamera, .externalUnknown]
        }
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
            .devices.map { DeviceOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }

    static func displayName(_ display: SCDisplay) -> String {
        let name = screen(for: display.displayID)?.localizedName ?? "Tela \(display.displayID)"
        return "\(name) · \(display.width)×\(display.height)"
    }
}

struct WindowOption: Identifiable, Hashable {
    let id: CGWindowID
    let name: String
}

extension DeviceCatalog {
    /// Janelas "de verdade" para gravar: visíveis, de tamanho razoável e de outros apps.
    static func recordableWindows(in content: SCShareableContent, excludingPID pid: pid_t) -> [SCWindow] {
        content.windows.filter { window in
            window.isOnScreen
                && window.windowLayer == 0
                && window.frame.width >= 200 && window.frame.height >= 150
                && window.owningApplication != nil
                && window.owningApplication?.processID != pid
        }
    }

    static func windowName(_ window: SCWindow) -> String {
        let app = window.owningApplication?.applicationName ?? "App"
        guard let title = window.title, !title.isEmpty else { return app }
        return "\(app) — \(title)"
    }

    static var maxBackingScale: CGFloat {
        NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }
}
