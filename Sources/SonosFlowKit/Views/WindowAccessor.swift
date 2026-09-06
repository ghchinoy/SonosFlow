import SwiftUI
import AppKit

/// SwiftUI helper to gain access to the underlying NSWindow for proxy icons and frame manipulation.
public struct WindowAccessor: NSViewRepresentable {
    public let onWindow: (NSWindow) -> Void

    public init(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowAccessView()
        view.onWindow = onWindow
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? WindowAccessView {
            view.onWindow = onWindow
            if let window = view.window {
                onWindow(window)
            }
        }
    }
}

private final class WindowAccessView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            onWindow?(window)
        }
    }
}
