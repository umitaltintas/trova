import Foundation
import CoreServices

/// `~/Library/Mail` ağacını FSEvents ile izler; değişiklikleri debounce edip bildirir.
/// Yeni mail geldiğinde otomatik (artımlı) indeksleme tetiklemek için.
final class MailWatcher: @unchecked Sendable {
    private let path: String
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?

    init(root: URL, onChange: @escaping @Sendable () -> Void) {
        self.path = root.path
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<MailWatcher>.fromOpaque(info).takeUnretainedValue().scheduleDebounced()
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,   // gecikme (s)
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents))
        else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Hızlı ardışık olayları tek bir bildirime indir (3 sn).
    private func scheduleDebounced() {
        debounce?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    deinit { stop() }
}
