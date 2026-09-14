import Foundation

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// Runs command-line tools (whisper-cli, claude, python) from inside the app.
enum Shell {
    static func run(_ executable: String, _ arguments: [String], cwd: URL? = nil, stdin: String? = nil,
                    env extra: [String: String] = [:]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd

        // Apps launched from Finder get a bare PATH; add the usual tool folders.
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env.removeValue(forKey: "CLAUDECODE")
        for (k, v) in extra { env[k] = v }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe = stdin == nil ? nil : Pipe()
        process.standardInput = inPipe

        try process.run()

        if let inPipe, let stdin {
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
        }

        // Read stderr on another thread so neither pipe can fill up and stall the tool.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
