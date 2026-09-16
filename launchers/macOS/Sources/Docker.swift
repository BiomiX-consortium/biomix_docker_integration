import Foundation
import AppKit
import Darwin

// MARK: - Configuration

enum Config {
    /// The container image to run. Tagged explicitly, like the Linux launcher.
    static let imageRef = "ghcr.io/biomix-consortium/biomix-gui:latest"
    /// Mount point inside the container.
    static let containerMountPath = "/shared"
    /// Port the Shiny server listens on inside the container.
    static let containerPort = 3838
    /// Host port to use when it is free; the launcher falls forward if it is not.
    static let preferredHostPort = 3838
    /// How many ports to try after the preferred one.
    static let portScanRange = 12
    /// QC preview for the "Undefined" data type, served by the same container.
    /// BiomiX links to it by number, so unlike the main port it cannot be remapped.
    static let qcPreviewPort = 3840
    /// Fixed name, so a container left running can be adopted on next launch.
    static let containerName = "biomix-gui"
    /// The daemon socket BiomiX uses to start its sibling analysis containers.
    static let dockerSocket = "/var/run/docker.sock"
    /// Extra flags for `docker run`, e.g. ["--platform", "linux/amd64"].
    static let extraRunFlags: [String] = []
    /// How long to wait for Shiny to answer before giving up.
    static let startupTimeout: TimeInterval = 120
}

// MARK: - Daemon state

enum DaemonState: Equatable {
    case checking
    case noClient                  // docker CLI not found on disk
    case notRunning(String)        // CLI found, daemon not answering
    case ready(version: String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - Docker CLI wrapper

struct DockerCLI {

    /// GUI apps launched from Finder do not inherit your shell PATH, so the
    /// binary has to be located explicitly.
    static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "\(home)/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/opt/podman/bin/docker",
            "/usr/bin/docker",
        ]
    }

    static func resolveBinary() -> String? {
        let fm = FileManager.default
        return searchPaths.first { fm.isExecutableFile(atPath: $0) }
    }

    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { status == 0 }
        /// Best available one-line explanation of a failure.
        var message: String {
            let source = stderr.isEmpty ? stdout : stderr
            let line = source.split(separator: "\n").first { !$0.isEmpty }
            return line.map(String.init) ?? "docker exited with status \(status)"
        }
    }

    /// Runs a docker subcommand with a hard timeout. Never call this on the main thread.
    @discardableResult
    static func run(_ arguments: [String], timeout: TimeInterval = 15) -> Result {
        guard let binary = resolveBinary() else {
            return Result(status: -1, stdout: "", stderr: "docker binary not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        // Drain both pipes concurrently so a chatty daemon cannot deadlock us.
        var outData = Data()
        var errData = Data()
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            drained.leave()
        }
        drained.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            drained.leave()
        }

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 2)
            }
        }
        drained.wait()

        func text(_ data: Data) -> String {
            String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // A killed process has no meaningful exit status, and reading
        // terminationStatus before it has actually reaped would trap, so say
        // plainly that we gave up instead.
        guard !timedOut else {
            return Result(status: -1,
                          stdout: text(outData),
                          stderr: "docker \(arguments.first ?? "") did not finish within \(Int(timeout))s.")
        }
        return Result(status: process.terminationStatus, stdout: text(outData), stderr: text(errData))
    }

    // MARK: Daemon

    /// `docker version` exits non-zero when the client is installed but the daemon is
    /// down, which makes it a cheap and unambiguous liveness probe.
    static func daemonState() -> DaemonState {
        guard resolveBinary() != nil else { return .noClient }
        let result = run(["version", "--format", "{{.Server.Version}}"], timeout: 12)
        if result.ok, !result.stdout.isEmpty {
            return .ready(version: result.stdout)
        }
        return .notRunning(result.stderr.isEmpty
                           ? "The Docker daemon is not responding."
                           : result.message)
    }

    static func imageIsPresentLocally() -> Bool {
        run(["image", "inspect", Config.imageRef], timeout: 15).ok
    }

    static func pullImage() -> Result {
        run(["pull", Config.imageRef], timeout: 1800)
    }

    static func dockerDesktopURL() -> URL? {
        let path = "/Applications/Docker.app"
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    /// Docker Desktop only creates `/var/run/docker.sock` when "Allow the default
    /// Docker socket to be used" is enabled. BiomiX starts its analysis containers
    /// through that socket, and bind-mounting a path that does not exist silently
    /// gives the container an empty directory instead — so check first, while we
    /// can still say something useful about it. (On Linux the socket is always there,
    /// which is why the reference script does not check.)
    static func defaultSocketIsAvailable() -> Bool {
        FileManager.default.fileExists(atPath: Config.dockerSocket)
    }

    // MARK: Container lifecycle

    struct ContainerInfo {
        let isRunning: Bool
        let hostPort: Int?
        let mountedPath: String?
    }

    /// Inspects the named container. Returns nil when no such container exists.
    ///
    /// State, mount and published port all come out of a single `docker inspect`:
    /// this runs on every poll, and each CLI invocation costs a process spawn.
    static func inspectContainer() -> ContainerInfo? {
        let mount = "{{range .Mounts}}{{if eq .Destination \"\(Config.containerMountPath)\"}}"
            + "{{.Source}}{{end}}{{end}}"
        // `range` rather than `index`: a stopped container has no port map, and
        // ranging over nil yields nothing while indexing it aborts the template
        // (which would read back here as "there is no such container").
        let ports = "{{range $port, $bindings := .NetworkSettings.Ports}}"
            + "{{if eq $port \"\(Config.containerPort)/tcp\"}}"
            + "{{range $bindings}}{{.HostPort}} {{end}}{{end}}{{end}}"
        let result = run(["inspect", "--format", "{{.State.Running}}\t\(mount)\t\(ports)",
                          Config.containerName], timeout: 12)
        guard result.ok else { return nil }

        let fields = result.stdout.components(separatedBy: "\t")
        func field(_ index: Int) -> String {
            index < fields.count ? fields[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }
        let mountedPath = field(1)
        return ContainerInfo(isRunning: field(0) == "true",
                             hostPort: field(2).split(separator: " ").compactMap { Int($0) }.first,
                             mountedPath: mountedPath.isEmpty ? nil : mountedPath)
    }

    /// Removes a leftover container using our name so a fresh start can proceed.
    static func removeStaleContainer() {
        run(["rm", "--force", Config.containerName], timeout: 20)
    }

    /// The exact `docker run` invocation. The window shows a rendering of this same
    /// array, so what the user reads can never drift from what actually runs.
    ///
    /// Deliberately no `--rm`: the container is detached, so when it dies during
    /// startup an auto-removed container would take its log — the one thing that
    /// explains the failure — with it. Leftovers are removed on the next start.
    static func runArguments(dataPath: String, hostPort: Int, ncbiAPIKey: String) -> [String] {
        var arguments = [
            "run", "--detach",
            "--name", Config.containerName,
            "-e", "BIOMIX_HOST_SHARED_PATH=\(dataPath)",
            "--publish", "127.0.0.1:\(hostPort):\(Config.containerPort)",
            "--publish", "127.0.0.1:\(Config.qcPreviewPort):\(Config.qcPreviewPort)",
            "--volume", "\(dataPath):\(Config.containerMountPath)",
            "--volume", "\(Config.dockerSocket):\(Config.dockerSocket)",
        ]
        let trimmedKey = ncbiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            arguments.append(contentsOf: ["-e", "NCBI_API_KEY=\(trimmedKey)"])
        }
        arguments.append(contentsOf: Config.extraRunFlags)
        arguments.append(Config.imageRef)
        return arguments
    }

    static func startContainer(dataDirectory: URL, hostPort: Int, ncbiAPIKey: String = "") -> Result {
        run(runArguments(dataPath: dataDirectory.path, hostPort: hostPort, ncbiAPIKey: ncbiAPIKey),
            timeout: 90)
    }

    @discardableResult
    static func stopContainer() -> Result {
        run(["stop", "--time", "8", Config.containerName], timeout: 40)
    }

    static func recentLogs(lines: Int = 40) -> String {
        let result = run(["logs", "--tail", "\(lines)", Config.containerName], timeout: 15)
        return [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: Rendering

    /// A copy-pasteable rendering of an argument list, one flag per line.
    static func commandLine(_ arguments: [String]) -> String {
        var groups: [[String]] = []
        for argument in arguments {
            if argument.hasPrefix("-") {
                groups.append([argument])
            } else if let last = groups.last, last.count == 1, last[0].hasPrefix("-") {
                groups[groups.count - 1].append(argument)   // a flag and its value
            } else {
                groups.append([argument])
            }
        }
        let lines = groups.map { $0.map(shellEscaped).joined(separator: " ") }
        guard let subcommand = lines.first else { return "docker" }
        return (["docker " + subcommand] + lines.dropFirst().map { "  " + $0 })
            .joined(separator: " \\\n")
    }

    private static let shellSafe = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:=+,@")

    static func shellEscaped(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        return value.unicodeScalars.allSatisfy(shellSafe.contains)
            ? value
            : TerminalLauncher.quote(value)
    }
}

// MARK: - Ports and readiness

enum LocalPort {

    /// True when nothing is currently listening on 127.0.0.1:port.
    static func isFree(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        // Docker's port proxy sets SO_REUSEADDR too. Without it a socket still in
        // TIME_WAIT from a previous session reads as "in use" when it is not.
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bound == 0
    }

    /// The preferred port if free, otherwise the next free one above it.
    ///
    /// The scan range covers the QC preview port, which the same container already
    /// publishes — handing it out here would make `docker run` collide with itself.
    static func pickHostPort() -> Int? {
        let start = Config.preferredHostPort
        for candidate in start...(start + Config.portScanRange)
        where candidate != Config.qcPreviewPort && isFree(candidate) {
            return candidate
        }
        return nil
    }

    /// True once the Shiny server answers an HTTP request on the loopback port.
    static func httpIsAnswering(port: Int, timeout: TimeInterval = 2.5) -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let waiter = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            box.answered = response is HTTPURLResponse
            waiter.signal()
        }
        task.resume()
        if waiter.wait(timeout: .now() + timeout + 1) == .timedOut {
            task.cancel()
            return false
        }
        return box.answered
    }

    private final class ResponseBox {
        var answered = false
    }
}

// MARK: - Terminal handoff (used for the log window only)

enum TerminalLauncher {

    /// Wraps a string so the shell treats it as one literal argument.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Opens a terminal window following the container log. Writing a .command file
    /// and letting Launch Services open it respects the user's default terminal and
    /// avoids the Automation permission prompt that AppleScript would trigger.
    static func followLogs() throws {
        let binary = DockerCLI.resolveBinary() ?? "docker"
        let command = "\(quote(binary)) logs --follow --tail 200 \(quote(Config.containerName))"
        let title = "BiomiX log"

        let script = """
        #!/bin/zsh
        printf '\\033]0;\(title)\\007'
        clear
        echo "\(title) — press Control-C to close"
        echo
        \(command)
        """

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BiomiXLauncher", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("biomix-logs.command")
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        NSWorkspace.shared.open(file)
    }
}
