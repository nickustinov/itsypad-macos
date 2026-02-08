import Foundation

final class FileWatcher {
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [URL: Int32] = [:]
    private var debounceWork: [URL: DispatchWorkItem] = [:]

    func watch(url: URL, callback: @escaping () -> Void) {
        stop(url: url)

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.debounceWork[url]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard self != nil else { return }
                DispatchQueue.main.async {
                    callback()
                }
            }
            self.debounceWork[url] = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        source.setCancelHandler {
            close(fd)
        }

        fileDescriptors[url] = fd
        sources[url] = source
        source.resume()
    }

    func stop(url: URL) {
        debounceWork[url]?.cancel()
        debounceWork.removeValue(forKey: url)
        sources[url]?.cancel()
        sources.removeValue(forKey: url)
        fileDescriptors.removeValue(forKey: url)
    }

    func stopAll() {
        for url in sources.keys {
            stop(url: url)
        }
    }
}
