import Foundation

/// Calls back whenever output/current.md changes on disk.
final class OutputWatcher {
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var lastModified: Date?

    func start() {
        let fd = open(Paths.output.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .extend], queue: .main)
        source.setEventHandler { [weak self] in self?.checkForChange() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        lastModified = currentModified()
    }

    private func checkForChange() {
        let now = currentModified()
        guard now != lastModified else { return }
        lastModified = now
        onChange?()
    }

    private func currentModified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Paths.current.path))?[.modificationDate] as? Date
    }
}
