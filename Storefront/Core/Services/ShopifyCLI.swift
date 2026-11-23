import AppKit
import Foundation
import OSLog
import os

private let shopifyCLILogger = Logger(subsystem: "com.humanmarketing.storefront", category: "ShopifyCLI")

/// Reads the stores a person can reach through the Shopify CLI (`shopify store list`).
///
/// Neither of Shopify's public APIs can do this: Admin API tokens belong to one store, and
/// the Partner API has no stores query. The CLI signs in with the person's own Shopify
/// account and lists every store in each organization they belong to, so Storefront
/// borrows that session instead of running its own OAuth.
enum ShopifyCLI {
    struct Organization: Decodable, Sendable, Equatable {
        let id: String
        let name: String
    }

    struct RemoteStore: Decodable, Sendable, Equatable {
        /// The `<handle>.myshopify.com` domain.
        let store: String
        let name: String?
        let primaryDomain: String?
        /// `dev`, `production`, `client-transfer` or `collaborator`.
        let type: String?
        let organizationName: String?
    }

    struct Snapshot: Sendable {
        let organizations: [Organization]
        let stores: [RemoteStore]
    }

    enum Failure: Error, Equatable {
        /// No `shopify` executable on the login shell's PATH.
        case notInstalled
        /// The CLI is installed but has no signed-in Shopify account.
        case notSignedIn(String)
        case failed(String)
    }

    static let installGuideURL = URL(string: "https://shopify.dev/docs/api/shopify-cli")!

    /// Every store across every organization the CLI account can reach, deduplicated by
    /// myshopify domain.
    static func fetchStores() async throws -> Snapshot {
        let environment = try await resolveEnvironment()
        let organizations = try await runJSON(
            environment,
            ["organization", "list", "--json", "--no-input"],
            as: OrganizationsEnvelope.self
        ).organizations

        guard !organizations.isEmpty else {
            return Snapshot(organizations: [], stores: [])
        }

        // `store list` leaves collaborator stores out unless asked for them by type, so
        // each organization needs two calls: the default list and the collaborator list.
        let requests: [[String]] = organizations.flatMap { organization in
            let base = ["store", "list", "--json", "--no-input", "--organization-id", organization.id]
            return [base, base + ["--type", "collaborator"]]
        }

        var collected: [RemoteStore] = []
        var lastFailure: Error?
        var succeeded = 0
        await withTaskGroup(of: Result<[RemoteStore], Error>.self) { group in
            for arguments in requests {
                group.addTask {
                    do {
                        let envelope = try await runJSON(environment, arguments, as: StoresEnvelope.self)
                        return .success(envelope.stores)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let stores):
                    succeeded += 1
                    collected.append(contentsOf: stores)
                case .failure(let error):
                    lastFailure = error
                    shopifyCLILogger.error("store list failed: \(String(describing: error), privacy: .public)")
                }
            }
        }

        // One type failing (say, no collaborator permission) still leaves a useful list.
        if succeeded == 0, let lastFailure { throw lastFailure }

        var seen = Set<String>()
        let unique = collected.filter { seen.insert($0.store.lowercased()).inserted }
        return Snapshot(organizations: organizations, stores: unique)
    }

    /// Opens Terminal running `shopify auth login`. The CLI's browser sign-in only runs in
    /// an interactive terminal, so it can't be driven from inside the app.
    static func openSignInInTerminal() async throws {
        let environment = try await resolveEnvironment()
        let script = """
        #!/bin/sh
        export PATH=\(shellQuoted(environment.path))
        clear
        echo "Signing in to Shopify for Storefront."
        echo
        \(shellQuoted(environment.executable.path)) auth login
        echo
        echo "All set. Close this window and go back to Storefront."
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Storefront Shopify Sign In.command")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
    }

    // MARK: - Environment

    private struct Environment: Sendable {
        let executable: URL
        let path: String

        var variables: [String: String] {
            var variables = ProcessInfo.processInfo.environment
            variables["PATH"] = path
            return variables
        }
    }

    private static let cachedEnvironment = OSAllocatedUnfairLock<Environment?>(initialState: nil)

    /// Apps launched from Finder get a bare PATH (`/usr/bin:/bin:…`), and the CLI is a Node
    /// script, so both `shopify` and `node` have to come from the PATH the person's login
    /// shell builds. Only a successful lookup is cached, so installing the CLI later works
    /// without relaunching.
    private static func resolveEnvironment() async throws -> Environment {
        if let cached = cachedEnvironment.withLock({ $0 }) { return cached }

        let shellPath = await loginShellPATH()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbacks = [
            "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/.npm-global/bin",
            "\(home)/Library/pnpm", "\(home)/.local/share/pnpm", "\(home)/.local/bin",
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        ]
        var components: [String] = []
        for component in (shellPath?.path ?? "").split(separator: ":").map(String.init) + fallbacks
        where !component.isEmpty && !components.contains(component) {
            components.append(component)
        }

        let candidates = [shellPath?.executable].compactMap { $0 }
            + components.map { "\($0)/shopify" }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Failure.notInstalled
        }

        let environment = Environment(executable: URL(fileURLWithPath: executable), path: components.joined(separator: ":"))
        cachedEnvironment.withLock { $0 = environment }
        return environment
    }

    /// Asks the person's login shell for its PATH and where `shopify` lives. Markers keep
    /// the answer apart from anything their rc files print.
    private static func loginShellPATH() async -> (path: String, executable: String?)? {
        let shell = userLoginShell()
        let command = #"printf '\n__STOREFRONT_PATH__=%s\n' "$PATH"; printf '__STOREFRONT_BIN__=%s\n' "$(command -v shopify)""#
        guard let output = try? await run(
            URL(fileURLWithPath: shell),
            ["-l", "-i", "-c", command],
            environment: nil,
            timeout: 10
        ) else { return nil }

        let text = String(decoding: output.data, as: UTF8.self)
        var path: String?
        var executable: String?
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("__STOREFRONT_PATH__=") {
                path = String(line.dropFirst("__STOREFRONT_PATH__=".count))
            } else if line.hasPrefix("__STOREFRONT_BIN__=") {
                let value = String(line.dropFirst("__STOREFRONT_BIN__=".count))
                if value.hasPrefix("/") { executable = value }
            }
        }
        guard let path else { return nil }
        return (path, executable)
    }

    private static func userLoginShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let value = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: value) { return value }
        }
        return "/bin/zsh"
    }

    // MARK: - Running commands

    private struct OrganizationsEnvelope: Decodable {
        let organizations: [Organization]
    }

    private struct StoresEnvelope: Decodable {
        let stores: [RemoteStore]
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable {
            let message: String
            let tryMessage: String?
        }
        let error: Body
    }

    private static func runJSON<T: Decodable>(_ environment: Environment, _ arguments: [String], as type: T.Type) async throws -> T {
        let output = try await run(environment.executable, arguments, environment: environment.variables, timeout: 60)
        let data = jsonPayload(output.data)
        let decoder = JSONDecoder()
        if let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
            throw classify(envelope.error.message)
        }
        if output.timedOut {
            throw Failure.failed("The Shopify CLI didn't answer within a minute.")
        }
        throw Failure.failed("The Shopify CLI exited with status \(output.status) without a readable answer.")
    }

    /// The CLI writes its JSON document to stdout, but an update notice can land in front
    /// of it, so start at the first `{`.
    private static func jsonPayload(_ data: Data) -> Data {
        guard let start = data.firstIndex(of: UInt8(ascii: "{")) else { return data }
        return data[start...]
    }

    private static func classify(_ message: String) -> Failure {
        let lowered = message.lowercased()
        let signInHints = ["log in", "logged in", "login", "auth", "alias", "session"]
        if signInHints.contains(where: lowered.contains) {
            return .notSignedIn(message)
        }
        return .failed(message)
    }

    private struct ProcessOutput {
        let status: Int32
        let data: Data
        let timedOut: Bool
    }

    /// Output goes to a temp file rather than a pipe: a pipe can deadlock once its buffer
    /// fills, and a background job started by someone's shell rc can hold a pipe open
    /// long after the shell itself exits.
    private static func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("storefront-cli-\(UUID().uuidString).out")
                guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
                      let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
                    continuation.resume(throwing: Failure.failed("Couldn't create a temporary file for the Shopify CLI."))
                    return
                }
                defer {
                    try? outputHandle.close()
                    try? FileManager.default.removeItem(at: outputURL)
                }

                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                if let environment { process.environment = environment }
                process.currentDirectoryURL = FileManager.default.temporaryDirectory
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = outputHandle
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: Failure.failed(error.localizedDescription))
                    return
                }

                let timedOut = OSAllocatedUnfairLock(initialState: false)
                let watchdog = DispatchWorkItem {
                    guard process.isRunning else { return }
                    timedOut.withLock { $0 = true }
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                process.waitUntilExit()
                watchdog.cancel()

                let data = (try? Data(contentsOf: outputURL)) ?? Data()
                continuation.resume(returning: ProcessOutput(
                    status: process.terminationStatus,
                    data: data,
                    timedOut: timedOut.withLock { $0 }
                ))
            }
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
