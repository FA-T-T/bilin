import Foundation

public enum RatexSVGCLIAdapterError: Error, Equatable, LocalizedError, Sendable {
    case missingExecutable
    case launchFailed(String)
    case timedOut
    case nonZeroExit(status: Int32, stderr: String)
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "RaTeX render-svg executable was not found. Set RATEX_RENDER_SVG_PATH or add render-svg to PATH."
        case .launchFailed(let message):
            return "RaTeX render-svg could not be launched: \(message)"
        case .timedOut:
            return "RaTeX render-svg timed out."
        case .nonZeroExit(let status, let stderr):
            return "RaTeX render-svg exited with status \(status): \(stderr)"
        case .invalidOutput(let output):
            return "RaTeX render-svg did not return SVG output: \(output)"
        }
    }
}

public struct RatexSVGCLIAdapter: RatexMathRenderingAdapter {
    public var executableURL: URL?
    public var fontDirectoryURL: URL?
    public var environment: [String: String]

    public init(
        executableURL: URL? = nil,
        fontDirectoryURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executableURL = executableURL
        self.fontDirectoryURL = fontDirectoryURL
        self.environment = environment
    }

    public func renderSVG(
        latex: String,
        mode: MathRenderMode,
        options: RatexRenderOptions
    ) throws -> String {
        guard let executableURL = executableURL ?? Self.discoveredExecutableURL(environment: environment) else {
            throw RatexSVGCLIAdapterError.missingExecutable
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments(mode: mode, options: options)
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let stdoutDrain = PipeDrain(pipe: stdout)
        let stderrDrain = PipeDrain(pipe: stderr)

        do {
            try process.run()
        } catch {
            throw RatexSVGCLIAdapterError.launchFailed(String(describing: error))
        }
        stdoutDrain.start()
        stderrDrain.start()

        if let input = "\(Self.cliFormulaLine(from: latex))\n".data(using: .utf8) {
            stdin.fileHandleForWriting.write(input)
        }
        stdin.fileHandleForWriting.closeFile()

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            finished.signal()
        }

        if finished.wait(timeout: .now() + options.timeoutSeconds) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
            stdoutDrain.close()
            stderrDrain.close()
            throw RatexSVGCLIAdapterError.timedOut
        }

        let output = String(data: stdoutDrain.wait(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderrDrain.wait(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw RatexSVGCLIAdapterError.nonZeroExit(
                status: process.terminationStatus,
                stderr: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let rawOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let svg = Self.extractSVG(from: rawOutput) else {
            throw RatexSVGCLIAdapterError.invalidOutput(rawOutput.isEmpty ? errorOutput : rawOutput)
        }
        return svg
    }

    public static func discoveredExecutableURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        if let explicitPath = environment["RATEX_RENDER_SVG_PATH"], !explicitPath.isEmpty {
            let url = URL(fileURLWithPath: explicitPath)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let path = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let candidates = ["render-svg", "ratex-render-svg"]
        for directory in path.split(separator: ":").map(String.init) {
            for candidate in candidates {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(candidate)
                if FileManager.default.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }

        if let home = environment["HOME"] {
            let cargoURL = URL(fileURLWithPath: home)
                .appendingPathComponent(".cargo/bin/render-svg")
            if FileManager.default.isExecutableFile(atPath: cargoURL.path) {
                return cargoURL
            }
        }

        guard environment["RATEX_DISABLE_COMMON_PATH_DISCOVERY"] != "1" else {
            return nil
        }

        for path in [
            "/opt/homebrew/bin/render-svg",
            "/usr/local/bin/render-svg",
            "/opt/homebrew/bin/ratex-render-svg",
            "/usr/local/bin/ratex-render-svg"
        ] {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    static func cliFormulaLine(from latex: String) -> String {
        latex
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractSVG(from output: String) -> String? {
        guard
            let openRange = output.range(of: "<svg", options: [.caseInsensitive]),
            let closeRange = output.range(
                of: "</svg>",
                options: [.caseInsensitive, .backwards],
                range: openRange.lowerBound..<output.endIndex
            )
        else {
            return nil
        }
        return String(output[openRange.lowerBound..<closeRange.upperBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func arguments(mode: MathRenderMode, options: RatexRenderOptions) -> [String] {
        var arguments = [
            "--stdout",
            "--font-size",
            String(options.fontSize),
            "--color",
            options.foregroundColor
        ]

        if let fontDirectoryURL = fontDirectoryURL {
            arguments += ["--font-dir", fontDirectoryURL.path]
        } else if let fontDirectoryPath = environment["RATEX_FONT_DIR"], !fontDirectoryPath.isEmpty {
            arguments += ["--font-dir", fontDirectoryPath]
        }

        if mode == .inline {
            arguments.append("--inline")
        }

        return arguments
    }
}

private final class PipeDrain: @unchecked Sendable {
    private let pipe: Pipe
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var data = Data()

    init(pipe: Pipe) {
        self.pipe = pipe
    }

    func start() {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let drainedData = self.pipe.fileHandleForReading.readDataToEndOfFile()
            self.lock.withLock {
                self.data = drainedData
            }
            self.group.leave()
        }
    }

    func wait() -> Data {
        group.wait()
        return lock.withLock { data }
    }

    func close() {
        pipe.fileHandleForReading.closeFile()
    }
}
