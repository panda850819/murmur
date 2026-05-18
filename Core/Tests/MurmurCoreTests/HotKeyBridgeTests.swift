#if os(macOS)
import XCTest
@testable import MurmurCore

@MainActor
private final class FakeHotKeyMonitor: HotKeyMonitoring {
    var onPress: (() -> Void)?
    var onRelease: ((_ cancelled: Bool) -> Void)?
    var startReturn = true
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() -> Bool { startCount += 1; return startReturn }
    func stop() { stopCount += 1 }

    // Test drivers — invoke what the real CGEvent tap would call.
    func firePress() { onPress?() }
    func fireRelease(cancelled: Bool) { onRelease?(cancelled) }
}

private final class FakeProbe: PermissionProbe {
    var ax: Bool
    var im: Bool
    init(ax: Bool, im: Bool) { self.ax = ax; self.im = im }
    func accessibilityTrusted(prompt: Bool) -> Bool { ax }
    func inputMonitoringTrusted(prompt: Bool) -> Bool { im }
}

@MainActor
private final class Rec: Recording {
    var isRecording = false
    var lastError: String?
    func start() async { isRecording = true }
    func stop() async -> URL? {
        isRecording = false
        return URL(fileURLWithPath: "/tmp/murmur-hotkey-test.wav")
    }
}

private struct Eng: Transcribing {
    func transcribe(wavURL: URL) async throws -> String { "ok" }
}

@MainActor
private final class Pst: Pasting {
    private(set) var pasted: [String] = []
    func paste(_ text: String) -> Bool { pasted.append(text); return true }
}

final class HotKeyBridgeTests: XCTestCase {
    @MainActor
    private func makeCoordinator(_ paster: Pst) -> DictationCoordinator {
        DictationCoordinator(
            recorder: Rec(),
            transcriber: Transcriber(engine: Eng()),
            paster: paster
        )
    }

    @MainActor
    func testAttachReadsPermissionsAndStartsOnce() {
        let mon = FakeHotKeyMonitor()
        let bridge = HotKeyBridge(monitor: mon, probe: FakeProbe(ax: true, im: true))
        bridge.attach(to: makeCoordinator(Pst()))
        XCTAssertTrue(bridge.accessibilityGranted)
        XCTAssertTrue(bridge.inputMonitoringGranted)
        XCTAssertTrue(bridge.allPermissionsGranted)
        XCTAssertEqual(mon.startCount, 1)

        bridge.attach(to: makeCoordinator(Pst())) // second attach is a no-op
        XCTAssertEqual(mon.startCount, 1)
    }

    @MainActor
    func testInputMonitoringFalseWhenProbeDenies() {
        let mon = FakeHotKeyMonitor()
        let bridge = HotKeyBridge(monitor: mon, probe: FakeProbe(ax: true, im: false))
        bridge.attach(to: makeCoordinator(Pst()))
        XCTAssertFalse(bridge.inputMonitoringGranted)
        XCTAssertTrue(bridge.accessibilityGranted)
        XCTAssertFalse(bridge.allPermissionsGranted)
    }

    @MainActor
    func testInputMonitoringFalseWhenTapCreationFails() {
        let mon = FakeHotKeyMonitor()
        mon.startReturn = false
        let bridge = HotKeyBridge(monitor: mon, probe: FakeProbe(ax: true, im: true))
        bridge.attach(to: makeCoordinator(Pst()))
        XCTAssertFalse(bridge.inputMonitoringGranted, "im && started — started=false")
    }

    @MainActor
    func testPressThenReleaseRunsToggleInOrder() async {
        let mon = FakeHotKeyMonitor()
        let paster = Pst()
        let coordinator = makeCoordinator(paster)
        let bridge = HotKeyBridge(monitor: mon, probe: FakeProbe(ax: true, im: true))
        bridge.attach(to: coordinator)

        mon.firePress()
        await bridge._waitForPending()
        XCTAssertEqual(coordinator.phase, .recording)

        mon.fireRelease(cancelled: false)
        await bridge._waitForPending()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(coordinator.transcript, "ok")
        XCTAssertEqual(paster.pasted, ["ok"])
    }

    @MainActor
    func testCancelledReleaseAbortsWithoutTranscribeOrPaste() async {
        let mon = FakeHotKeyMonitor()
        let paster = Pst()
        let coordinator = makeCoordinator(paster)
        let bridge = HotKeyBridge(monitor: mon, probe: FakeProbe(ax: true, im: true))
        bridge.attach(to: coordinator)

        mon.firePress()
        await bridge._waitForPending()
        XCTAssertEqual(coordinator.phase, .recording)

        mon.fireRelease(cancelled: true)
        await bridge._waitForPending()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertNil(coordinator.transcript)
        XCTAssertTrue(paster.pasted.isEmpty)
    }

    @MainActor
    func testRetryStopsThenStartsAndRereadsProbe() {
        let mon = FakeHotKeyMonitor()
        let probe = FakeProbe(ax: false, im: false)
        let bridge = HotKeyBridge(monitor: mon, probe: probe)
        bridge.attach(to: makeCoordinator(Pst()))
        XCTAssertFalse(bridge.allPermissionsGranted)
        XCTAssertEqual(mon.startCount, 1)

        probe.ax = true
        probe.im = true
        bridge.retry()
        XCTAssertEqual(mon.stopCount, 1)
        XCTAssertEqual(mon.startCount, 2)
        XCTAssertTrue(bridge.allPermissionsGranted)
    }
}
#endif
