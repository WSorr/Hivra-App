import Cocoa
import Darwin
import FlutterMacOS

// Keep the descriptor open: process exit releases the lock without a stale PID file.
final class RuntimeInstanceLock {
  private let descriptor: Int32

  private init(descriptor: Int32) {
    self.descriptor = descriptor
  }

  static func acquire(at url: URL) throws -> RuntimeInstanceLock? {
    let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let error = errno
      close(descriptor)
      if error == EWOULDBLOCK { return nil }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(error))
    }
    return RuntimeInstanceLock(descriptor: descriptor)
  }

  deinit {
    close(descriptor)
  }
}

class MainFlutterWindow: NSWindow {
  private static var runtimeLock: RuntimeInstanceLock?

  override func awakeFromNib() {
    if let bundleIdentifier = Bundle.main.bundleIdentifier,
       let existing = NSRunningApplication.runningApplications(
         withBundleIdentifier: bundleIdentifier
       ).first(where: {
         $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
           $0.isFinishedLaunching && !$0.isTerminated
       }) {
      existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
      exit(EXIT_SUCCESS)
    }

    do {
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true
      ).appendingPathComponent("Hivra", isDirectory: true)
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
      Self.runtimeLock = try RuntimeInstanceLock.acquire(
        at: support.appendingPathComponent("runtime.lock")
      )
      guard Self.runtimeLock != nil else { exit(EXIT_SUCCESS) }
    } catch {
      let alert = NSAlert()
      alert.messageText = "Hivra cannot open its local runtime"
      alert.informativeText = "Check access to Application Support/Hivra and try again."
      alert.runModal()
      exit(EXIT_FAILURE)
    }

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
