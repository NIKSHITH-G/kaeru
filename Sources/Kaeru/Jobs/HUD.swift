import AppKit
import SwiftUI

/// Progress cards in the top-right corner. They stay while you hover and fade a few seconds after jobs finish.
@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    fileprivate var hovering = false {
        didSet { if !hovering { scheduleHide() } }
    }

    func show() {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
    }

    func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel, !self.hovering,
                  !JobCenter.shared.jobs.contains(where: \.isRunning) else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
                Task { @MainActor in panel.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        let host = NSHostingView(rootView: HUDView(center: JobCenter.shared))
        host.frame = panel.contentLayoutRect
        panel.contentView = host
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 8, y: screen.maxY - panel.frame.height - 6))
    }
}

private struct HUDView: View {
    @ObservedObject var center: JobCenter

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.jobs.prefix(3)) { job in
                JobCard(job: job)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.jobs.prefix(3).map(\.id))
        .padding(12)
        .frame(width: 340, height: 300, alignment: .topTrailing)
        .onHover { HUD.shared.hovering = $0 }
    }
}

/// One job: thumbnail, name, progress or result, and the actions that make sense for its state.
struct JobCard: View {
    @ObservedObject var job: Job
    var compact = true

    var body: some View {
        HStack(spacing: 11) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(job.title).font(.system(size: 12, weight: .semibold))
                    Text(job.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                detail
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: compact ? 316 : nil)
        .background(compact ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(compact ? RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)) : nil)
        .shadow(color: .black.opacity(compact ? 0.15 : 0), radius: 10, y: 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { job.open() }
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = job.thumbnail {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc").font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            badge.offset(x: 5, y: 5)
        }
    }

    @ViewBuilder private var badge: some View {
        switch job.state {
        case .done: status("checkmark.circle.fill", .green)
        case .failed: status("exclamationmark.circle.fill", .orange)
        default: EmptyView()
        }
    }

    private func status(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(.white, color)
            .background(Circle().fill(.background).padding(1))
    }

    @ViewBuilder private var detail: some View {
        switch job.state {
        case .running(let p):
            HStack(spacing: 8) {
                if let p {
                    ProgressView(value: p).progressViewStyle(.linear).tint(Theme.brand.swiftUI)
                    Text("\(Int(p * 100))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(Theme.brand.swiftUI)
                }
            }
        case .done(let r):
            Text(r.message ?? (r.outputs.isEmpty ? "Done" : r.outputs.map(\.lastPathComponent).joined(separator: ", ")))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(compact ? 1 : 2).truncationMode(.middle)
        case .failed(let message):
            Text(message).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(compact ? 2 : 4).textSelection(.enabled)
        case .cancelled:
            Text("Cancelled").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var actions: some View {
        switch job.state {
        case .running:
            iconButton("xmark", help: "Cancel") { job.cancel() }
        case .done where !job.existingOutputs.isEmpty:
            HStack(spacing: 2) {
                iconButton("arrow.up.forward.app", help: "Open") { job.open() }
                iconButton("folder", help: "Show in Finder") { job.reveal() }
            }
        case .failed(let message):
            iconButton("doc.on.doc", help: "Copy error") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
            }
        default: EmptyView()
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
                .background(Circle().fill(.quaternary))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
