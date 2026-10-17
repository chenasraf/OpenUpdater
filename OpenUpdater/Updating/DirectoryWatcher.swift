//
//  DirectoryWatcher.swift
//  OpenUpdater
//

import CoreServices
import Foundation

/// Calls `onChange` on the main queue whenever anything under the watched directories
/// changes. FSEvents watches recursively and coalesces bursts within `latency`, so a
/// copy into `/Applications` (thousands of file writes) arrives as one or two calls.
final class DirectoryWatcher {
  private var stream: FSEventStreamRef?
  private let onChange: () -> Void

  init(paths: [URL], latency: TimeInterval = 2, onChange: @escaping () -> Void) {
    self.onChange = onChange
    var context = FSEventStreamContext(
      version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil, release: nil, copyDescription: nil)
    let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
      guard let info else { return }
      let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
      MainActor.assumeIsolated { watcher.onChange() }
    }
    guard
      let stream = FSEventStreamCreate(
        nil, callback, &context, paths.map(\.path) as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
    else { return }
    FSEventStreamSetDispatchQueue(stream, .main)
    FSEventStreamStart(stream)
    self.stream = stream
  }

  deinit {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
  }
}
