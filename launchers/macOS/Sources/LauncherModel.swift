import Foundation
import SwiftUI
import AppKit

// MARK: - Session state

enum SessionState: Equatable {
    case idle
    case downloadingImage
    case starting(String)          // progress detail shown under the spinner
    case running(port: Int)
    case stopping
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .downloadingImage, .starting, .stopping: return true
        default: return false
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

// MARK: - Model

final class LauncherModel: ObservableObject {

    @Published private(set) var daemon: DaemonState = .checking
    @Published private(set) var imageIsLocal: Bool?
    @Published private(set) var session: SessionState = .idle
    @Published private(set) var isRefreshing = false
    @Published var dataDirectory: URL?
    @Published var lastError: String?

    private let dataDirectoryKey = "dataDirectoryPath"
    private var pollTimer: Timer?
    private let work = DispatchQueue(label: "org.biomix.launcher.work", qos: .userInitiated)

    init() {
        if let saved = UserDefaults.standard.string(forKey: dataDirectoryKey),
           isDirectory(saved) {
            dataDirectory = URL(fileURLWithPath: saved, isDirectory: true)
        }
    }

    // MARK: Status polling

    func startMonitoring() {
        guard pollTimer == nil else { return }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Checks the daemon, and adopts or releases the container if its state changed
    /// behind our back (user stopped it in Docker Desktop, R crashed, and so on).
    func refresh() {
        guard !isRefreshing, !session.isBusy else { return }
        isRefreshing = true
        work.async { [weak self] in
            let daemonState = DockerCLI.daemonState()
            let hasImage = daemonState.isReady ? DockerCLI.imageIsPresentLocally() : nil
            let container = daemonState.isReady ? DockerCLI.inspectContainer() : nil

            DispatchQueue.main.async {
                guard let self else { return }
                self.daemon = daemonState
                self.imageIsLocal = hasImage
                self.isRefreshing = false
                self.reconcile(with: container, daemonReady: daemonState.isReady)
            }
        }
    }

    private func reconcile(with container: DockerCLI.ContainerInfo?, daemonReady: Bool) {
        guard !session.isBusy else { return }

        guard daemonReady else {
            if session.isRunning { session = .idle }
            return
        }

        if let container, container.isRunning, let port = container.hostPort {
            // Adopt a container that is already up, including across app restarts.
            if case .running(let known) = session, known == port { return }
            if let mounted = container.mountedPath, dataDirectory == nil {
                setDataDirectory(URL(fileURLWithPath: mounted, isDirectory: true))
            }
            session = .running(port: port)
        } else if session.isRunning {
            session = .failed("The BiomiX container stopped. Check the log for details.")
        }
    }

    // MARK: Data directory

    var canStart: Bool {
        daemon.isReady && dataDirectory != nil && !session.isBusy && !session.isRunning
    }

    func chooseDataDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        panel.message = "Pick the folder BiomiX should read and write. "
            + "It appears as \(Config.containerMountPath) inside the app."
        panel.directoryURL = dataDirectory ?? FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            setDataDirectory(url)
        }
    }

    func setDataDirectory(_ url: URL) {
        dataDirectory = url
        UserDefaults.standard.set(url.path, forKey: dataDirectoryKey)
        lastError = nil
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !session.isRunning, !session.isBusy else { return false }
        guard let provider = providers.first else { return false }
        let type = "public.file-url"
        guard provider.hasItemConformingToTypeIdentifier(type) else { return false }

        provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let direct = item as? URL {
                url = direct
            }
            guard let url, let self, self.isDirectory(url.path) else { return }
            DispatchQueue.main.async { self.setDataDirectory(url) }
        }
        return true
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    // MARK: Session URL

    var sessionURL: URL? {
        guard case .running(let port) = session else { return nil }
        return URL(string: "http://localhost:\(port)")
    }

    var usingFallbackPort: Bool {
        guard case .running(let port) = session else { return false }
        return port != Config.preferredHostPort
    }

    /// Readable equivalent of what the launcher runs, shown in the window.
    var displayCommand: String {
        let directory = dataDirectory?.path ?? "LOCAL_DIR"
        var port = Config.preferredHostPort
        if case .running(let active) = session { port = active }
        return "docker run -d --rm --name \(Config.containerName) "
            + "-p \(port):\(Config.containerPort) "
            + "-v \(directory):\(Config.containerMountPath) \(Config.imageRef)"
    }

    // MARK: Start

    func start() {
        guard let directory = dataDirectory else { return }
        guard isDirectory(directory.path) else {
            dataDirectory = nil
            session = .failed("That folder no longer exists. Pick it again.")
            return
        }

        lastError = nil
        let needsImage = imageIsLocal == false
        session = needsImage ? .downloadingImage : .starting("Starting the container…")

        work.async { [weak self] in
            if needsImage {
                let pull = DockerCLI.pullImage()
                guard pull.ok else {
                    self?.finish(.failed("Could not download the image: \(pull.message)"))
                    return
                }
                DispatchQueue.main.async { self?.imageIsLocal = true }
                self?.report("Starting the container…")
            }

            // Clear any leftover container holding our name.
            if let existing = DockerCLI.inspectContainer() {
                if existing.isRunning, let port = existing.hostPort {
                    self?.finish(.running(port: port))
                    return
                }
                DockerCLI.removeStaleContainer()
            }

            guard let port = LocalPort.pickHostPort() else {
                self?.finish(.failed(
                    "Ports \(Config.preferredHostPort)–\(Config.preferredHostPort + Config.portScanRange) "
                    + "are all in use. Quit whatever is using them and try again."))
                return
            }

            let run = DockerCLI.startContainer(dataDirectory: directory, hostPort: port)
            guard run.ok else {
                self?.finish(.failed("Docker could not start the container: \(run.message)"))
                return
            }

            self?.report("Waiting for the R session to come up…")
            let deadline = Date().addingTimeInterval(Config.startupTimeout)
            var checks = 0

            while Date() < deadline {
                if LocalPort.httpIsAnswering(port: port) {
                    self?.finish(.running(port: port))
                    DispatchQueue.main.async { self?.openInBrowser() }
                    return
                }
                checks += 1
                // Every few attempts, confirm the container is still alive.
                if checks % 3 == 0 {
                    let info = DockerCLI.inspectContainer()
                    if info == nil || info?.isRunning == false {
                        let log = DockerCLI.recentLogs(lines: 12)
                        DockerCLI.removeStaleContainer()
                        self?.finish(.failed(log.isEmpty
                            ? "The container exited during startup."
                            : "The container exited during startup:\n\(log.suffix(400))"))
                        return
                    }
                }
                Thread.sleep(forTimeInterval: 1.5)
            }

            self?.finish(.failed(
                "BiomiX did not answer on port \(port) within "
                + "\(Int(Config.startupTimeout)) seconds. It may still be loading — "
                + "open the log to check."))
        }
    }

    // MARK: Stop

    func stop() {
        guard session.isRunning else { return }
        session = .stopping
        work.async { [weak self] in
            let result = DockerCLI.stopContainer()
            self?.finish(result.ok ? .idle : .failed("Could not stop the container: \(result.message)"))
        }
    }

    /// Blocking stop, used when the app is quitting.
    func stopSynchronously() {
        DockerCLI.stopContainer()
    }

    var containerIsRunning: Bool { session.isRunning }

    // MARK: Actions

    func openInBrowser() {
        guard let url = sessionURL else { return }
        NSWorkspace.shared.open(url)
    }

    func copyLink() {
        guard let url = sessionURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func showLogs() {
        do {
            try TerminalLauncher.followLogs()
        } catch {
            lastError = "Could not open the log window: \(error.localizedDescription)"
        }
    }

    func startDockerDesktop() {
        guard let url = DockerCLI.dockerDesktopURL() else {
            lastError = "Docker Desktop is not in your Applications folder."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func downloadImage() {
        guard !session.isBusy else { return }
        session = .downloadingImage
        work.async { [weak self] in
            let result = DockerCLI.pullImage()
            if result.ok {
                DispatchQueue.main.async { self?.imageIsLocal = true }
                self?.finish(.idle)
            } else {
                self?.finish(.failed("Could not download the image: \(result.message)"))
            }
        }
    }

    func dismissFailure() {
        if case .failed = session { session = .idle }
    }

    // MARK: Helpers

    private func report(_ detail: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session.isBusy else { return }
            self.session = .starting(detail)
        }
    }

    private func finish(_ state: SessionState) {
        DispatchQueue.main.async { [weak self] in
            self?.session = state
        }
    }
}
