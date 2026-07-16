import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  func applicationShouldFinishLaunching(_ notification: Notification) -> Bool {
    UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    NSWindow.allowsAutomaticWindowTabbing = false
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
    }
    sender.activate(ignoringOtherApps: true)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return false
  }

  func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
    return false
  }

  func application(_ application: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
    return false
  }
}
