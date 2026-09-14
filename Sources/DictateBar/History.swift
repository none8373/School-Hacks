import Foundation

/// Appends every AI run to output/history.log so problems can be traced afterwards.
enum History {
    static let url = Paths.output.appendingPathComponent("history.log")

    static func record(mode: String, provider: String, input: String, output: String?, error: String?, seconds: Double) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var entry = "==== \(f.string(from: Date()))  mode=\(mode)  provider=\(provider)  took=\(String(format: "%.1f", seconds))s\n"
        entry += "-- input\n\(input)\n"
        if let output { entry += "-- output\n\(output)\n" }
        if let error { entry += "-- error\n\(error)\n" }
        entry += "\n"
        let data = Data(entry.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
