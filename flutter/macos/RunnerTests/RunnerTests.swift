import Cocoa
import FlutterMacOS
import XCTest
@testable import hivra_app

class RunnerTests: XCTestCase {

  func testRuntimeLockRejectsSecondOwnerAndAllowsReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("runtime.lock")
    var first = try RuntimeInstanceLock.acquire(at: url)
    XCTAssertNotNil(first)
    XCTAssertNil(try RuntimeInstanceLock.acquire(at: url))
    first = nil
    XCTAssertNotNil(try RuntimeInstanceLock.acquire(at: url))
  }

  func testRuntimeLockFailsForUnavailableStorage() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("runtime.lock")
    XCTAssertThrowsError(try RuntimeInstanceLock.acquire(at: url))
  }

  func testRuntimeLockRejectsSymlink() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("target")
    let url = directory.appendingPathComponent("runtime.lock")
    try Data().write(to: target)
    try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
    XCTAssertThrowsError(try RuntimeInstanceLock.acquire(at: url))
  }

}
