import SwiftUI
import AppKit

/// PopoverHost 구조체를 정의합니다.
struct PopoverHost<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismissPanel()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            if context.coordinator.panel == nil {
                context.coordinator.showPanel(from: nsView, content: content)
            } else {
                context.coordinator.updateContent(content)
            }
        } else {
            context.coordinator.dismissPanel()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    class Coordinator: NSObject {
        @Binding var isPresented: Bool
        var panel: NSPanel?
        var hostingView: NSHostingView<AnyView>?
        var localEventMonitor: Any?
        var globalEventMonitor: Any?
        var appDeactivateObserver: NSObjectProtocol?

        init(isPresented: Binding<Bool>) {
            self._isPresented = isPresented
        }

        func showPanel<V: View>(from parentView: NSView, content: () -> V) {
            guard let parentWindow = parentView.window else { return }

            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .popUpMenu
            panel.hasShadow = true
            panel.collectionBehavior = [.fullScreenAuxiliary]

            panel.becomesKeyOnlyIfNeeded = true

            let hosting: NSHostingView<AnyView> = NSHostingView(rootView: AnyView(content().preferredColorScheme(.dark)))
            hosting.frame.size = hosting.fittingSize
            panel.contentView = hosting
            panel.setContentSize(hosting.fittingSize)
            self.hostingView = hosting

            let parentFrame = parentView.convert(parentView.bounds, to: nil)
            let screenFrame = parentWindow.convertToScreen(parentFrame)
            let panelOrigin = NSPoint(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y - panel.frame.height - 4
            )
            panel.setFrameOrigin(panelOrigin)

            parentWindow.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            self.panel = panel

            let triggerFrame = parentWindow.convertToScreen(parentView.convert(parentView.bounds, to: nil))

            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self, let panel = self.panel else { return event }
                let mouseLocation = NSEvent.mouseLocation
                let isInPanel = panel.frame.contains(mouseLocation)
                let isInTrigger = triggerFrame.contains(mouseLocation)
                if !isInPanel && !isInTrigger {
                    self.dismissPanel()
                }
                return event
            }

            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.dismissPanel()
            }

            appDeactivateObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.dismissPanel()
            }
        }

        func updateContent<V: View>(_ content: () -> V) {
            guard let hostingView = hostingView else { return }
            hostingView.rootView = AnyView(content().preferredColorScheme(.dark))
            let newSize = hostingView.fittingSize
            if let panel = panel, panel.frame.size != newSize {
                panel.setContentSize(newSize)
            }
        }

        func dismissPanel() {
            if let monitor = localEventMonitor {
                NSEvent.removeMonitor(monitor)
                localEventMonitor = nil
            }
            if let monitor = globalEventMonitor {
                NSEvent.removeMonitor(monitor)
                globalEventMonitor = nil
            }
            if let observer = appDeactivateObserver {
                NotificationCenter.default.removeObserver(observer)
                appDeactivateObserver = nil
            }
            if let panel = panel, let parent = panel.parent {
                parent.removeChildWindow(panel)
            }
            panel?.orderOut(nil)
            panel = nil
            hostingView = nil
            if isPresented {
                isPresented = false
            }
        }

        deinit {
            if let monitor = localEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = globalEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let observer = appDeactivateObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
