import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Entry point

@main
struct BiomiXLauncherApp: App {
    @StateObject private var model = LauncherModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("BiomiX Launcher") {
            LauncherView(model: model)
                .onAppear { delegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

/// Offers to stop the container when the app quits, so users don't leave an
/// orphaned Shiny server holding the port.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: LauncherModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.containerIsRunning else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "BiomiX is still running."
        alert.informativeText = "Stop the session before quitting? "
            + "Leaving it running keeps the browser link working."
        alert.addButton(withTitle: "Stop and quit")
        alert.addButton(withTitle: "Leave running")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.stopSynchronously()
            return .terminateNow
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}

// MARK: - Palette

private extension Color {
    static let accentTeal = Color(red: 0.05, green: 0.44, blue: 0.45)
    static let live = Color(red: 0.16, green: 0.72, blue: 0.35)
    static let waiting = Color(red: 0.95, green: 0.64, blue: 0.15)
    static let down = Color(red: 0.85, green: 0.28, blue: 0.28)
}

// MARK: - Main view

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            masthead
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                statusRow
                folderPicker
                sessionArea
            }
            .padding(22)
        }
        .frame(width: 470)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.startMonitoring() }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { model.acceptDrop($0) }
        .animation(.easeInOut(duration: 0.18), value: model.session)
    }

    // MARK: Masthead

    private var masthead: some View {
        HStack(spacing: 14) {
            logo.frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("BiomiX")
                    .font(.system(size: 22, weight: .semibold))
                Text("Containerized analysis workspace")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 20)
    }

    private var logo: some View {
        Group {
            if let image = Self.bundledLogo {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentTeal.opacity(0.12))
                    .overlay(
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Color.accentTeal)
                    )
            }
        }
    }

    /// Drop a `logo.png` (or .pdf/.jpg) into Resources/ and it is picked up here.
    private static let bundledLogo: NSImage? = {
        for ext in ["png", "pdf", "icns", "jpg"] {
            if let url = Bundle.main.url(forResource: "logo", withExtension: ext),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }()

    // MARK: Docker status

    private var statusRow: some View {
        HStack(spacing: 10) {
            StatusDot(color: statusColor, pulsing: model.daemon == .checking)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusHeadline)
                    .font(.system(size: 13, weight: .medium))
                Text(statusDetail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            statusAction
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(statusColor.opacity(0.28), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch model.daemon {
        case .checking:   return .secondary
        case .noClient:   return .down
        case .notRunning: return .waiting
        case .ready:      return .live
        }
    }

    private var statusHeadline: String {
        switch model.daemon {
        case .checking:   return "Checking Docker"
        case .noClient:   return "Docker is not installed"
        case .notRunning: return "Docker is not running"
        case .ready:      return "Docker is running"
        }
    }

    private var statusDetail: String {
        switch model.daemon {
        case .checking:
            return "Contacting the daemon…"
        case .noClient:
            return "No docker binary found in the usual locations."
        case .notRunning(let reason):
            return reason
        case .ready(let version):
            let image = model.imageIsLocal == false ? " · image not downloaded yet" : ""
            return "engine \(version)\(image)"
        }
    }

    @ViewBuilder
    private var statusAction: some View {
        switch model.daemon {
        case .notRunning where DockerCLI.dockerDesktopURL() != nil:
            Button("Start Docker") { model.startDockerDesktop() }
                .controlSize(.small)
        case .noClient:
            Link("Install", destination: URL(string: "https://www.docker.com/products/docker-desktop/")!)
                .controlSize(.small)
        case .ready where model.imageIsLocal == false:
            Button("Download image") { model.downloadImage() }
                .controlSize(.small)
                .disabled(model.session.isBusy)
        default:
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .controlSize(.small)
                .help("Check again")
        }
    }

    // MARK: Folder picker

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("Data folder")
                    .font(.system(size: 13, weight: .medium))
                if model.session.isRunning {
                    Text("locked while running")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: model.dataDirectory == nil ? "folder.badge.questionmark" : "folder.fill")
                    .foregroundStyle(model.dataDirectory == nil ? .secondary : Color.accentTeal)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.dataDirectory?.lastPathComponent ?? "No folder selected")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Text(model.dataDirectory?.deletingLastPathComponent().path
                         ?? "Choose a folder, or drag one onto this window")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 8)
                Button(model.dataDirectory == nil ? "Choose…" : "Change…") {
                    model.chooseDataDirectory()
                }
                .controlSize(.small)
                .disabled(model.session.isRunning || model.session.isBusy)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isDropTarget ? Color.accentTeal : Color.primary.opacity(0.08),
                                  style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1,
                                                     dash: model.dataDirectory == nil ? [4, 3] : []))
            )
            .opacity(model.session.isRunning ? 0.6 : 1)
        }
    }

    // MARK: Session area

    @ViewBuilder
    private var sessionArea: some View {
        switch model.session {
        case .running:
            runningCard
        case .starting(let detail):
            busyCard(detail, showLogButton: true)
        case .downloadingImage:
            busyCard("Downloading the BiomiX image. First run only, and it is a large download.",
                     showLogButton: false)
        case .stopping:
            busyCard("Stopping the session…", showLogButton: false)
        case .failed(let reason):
            failureCard(reason)
        case .idle:
            idleCard
        }
    }

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            commandReadout
            HStack {
                if !model.canStart {
                    Text(model.daemon.isReady ? "Pick a data folder to continue" : "Waiting for Docker")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.start()
                } label: {
                    Label("Start BiomiX", systemImage: "play.fill").padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentTeal)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStart)
            }
        }
    }

    /// The link is the point of the whole app, so it gets the loudest treatment.
    private var runningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatusDot(color: .live, pulsing: false)
                Text("BiomiX is running")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.usingFallbackPort {
                    Text("port \(Config.preferredHostPort) was busy")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text(model.sessionURL?.absoluteString ?? "")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button {
                    model.copyLink()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .controlSize(.small)
                .help("Copy the link")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentTeal.opacity(0.10))
            )

            HStack(spacing: 10) {
                Button {
                    model.openInBrowser()
                } label: {
                    Label("Open in browser", systemImage: "arrow.up.forward.app")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentTeal)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Spacer()
                Button("Log") { model.showLogs() }
                    .controlSize(.large)
                Button("Stop") { model.stop() }
                    .controlSize(.large)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.live.opacity(0.35), lineWidth: 1)
        )
    }

    private func busyCard(_ detail: String, showLogButton: Bool) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if showLogButton {
                Button("Log") { model.showLogs() }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func failureCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Could not start BiomiX", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.down)
            Text(reason)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Log") { model.showLogs() }
                    .controlSize(.small)
                Spacer()
                Button("Dismiss") { model.dismissFailure() }
                    .controlSize(.small)
                Button("Try again") { model.start() }
                    .controlSize(.small)
                    .disabled(model.dataDirectory == nil || !model.daemon.isReady)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.down.opacity(0.07))
        )
    }

    private var commandReadout: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Runs this command")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(model.displayCommand)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
        }
    }
}

// MARK: - Status dot

private struct StatusDot: View {
    let color: Color
    let pulsing: Bool
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: 3)
                    .scaleEffect(animate ? 1.9 : 1.0)
                    .opacity(animate ? 0 : 1)
            )
            .shadow(color: color.opacity(0.6), radius: 4)
            .onAppear { updateAnimation() }
            .onChange(of: pulsing) { _ in updateAnimation() }
    }

    private func updateAnimation() {
        guard pulsing else {
            animate = false
            return
        }
        withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
            animate = true
        }
    }
}
