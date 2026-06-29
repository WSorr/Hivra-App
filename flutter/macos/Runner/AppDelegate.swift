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
