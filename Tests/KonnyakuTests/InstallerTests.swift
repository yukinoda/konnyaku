import XCTest
@testable import Konnyaku

/// Uses fixtures in a temporary directory only; never touches real installs,
/// mounted disks or the Trash.
final class InstallerTests: XCTestCase {
    private let files = FileManager.default
    private var root: URL!
    private var app: URL!
    private var source: URL!
    private var image: URL!
    private var entry: [String: Any]!

    override func setUpWithError() throws {
        root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app = root.appendingPathComponent("Applications/Konnyaku.app")
        source = root.appendingPathComponent("Volume/Konnyaku.app")
        try makeBundle(at: app)
        try makeBundle(at: source)
        image = root.appendingPathComponent("Konnyaku-0.1.0-arm64.dmg")
        try Data().write(to: image)
        entry = [
            "image-path": image.path,
            "system-entities": [["mount-point": source.deletingLastPathComponent().path]],
        ]
    }

    override func tearDownWithError() throws {
        try files.removeItem(at: root)
    }

    private func makeBundle(at bundle: URL) throws {
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try files.createDirectory(at: macOS, withIntermediateDirectories: true)
        try writeInfo(to: bundle, version: "0.1.0")
        try Data("build".utf8).write(to: macOS.appendingPathComponent("Konnyaku"))
    }

    private func writeInfo(to bundle: URL, version: String) throws {
        let info = [
            "CFBundleIdentifier": "io.github.yukinoda.konnyaku",
            "CFBundleShortVersionString": version,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    }

    func testOnlyAppsInApplicationsCount() throws {
        let applications = [app.deletingLastPathComponent()]
        XCTAssertTrue(Installer.isInApplications(app, directories: applications))
        XCTAssertFalse(Installer.isInApplications(source, directories: applications))

        let linked = app.deletingLastPathComponent().appendingPathComponent("Linked.app")
        try files.createSymbolicLink(at: linked, withDestinationURL: source)
        XCTAssertFalse(Installer.isInApplications(linked, directories: applications))
    }

    func testMatchingBuildIsFound() {
        let match = Installer.find(for: app, images: [entry])
        XCTAssertEqual(match?.image, image)
        XCTAssertEqual(match?.volume, source.deletingLastPathComponent())
        XCTAssertEqual(match?.imageIsCurrent(), true)
    }

    func testNoImagesOrNonDMGFindsNothing() {
        XCTAssertNil(Installer.find(for: app, images: []))
        let notDMG: [String: Any] = [
            "image-path": app.path,
            "system-entities": [["mount-point": source.deletingLastPathComponent().path]],
        ]
        XCTAssertNil(Installer.find(for: app, images: [notDMG]))
    }

    func testDifferentExecutableIsRejected() throws {
        let executable = source.appendingPathComponent("Contents/MacOS/Konnyaku")
        try Data("different build".utf8).write(to: executable)
        XCTAssertNil(Installer.find(for: app, images: [entry]))
    }

    func testDifferentVersionIsRejected() throws {
        try writeInfo(to: source, version: "0.2.0")
        XCTAssertNil(Installer.find(for: app, images: [entry]))
    }

    func testReplacedImageIsNotCurrent() throws {
        let match = try XCTUnwrap(Installer.find(for: app, images: [entry]))
        try Data("replacement".utf8).write(to: image, options: .atomic)
        XCTAssertFalse(match.imageIsCurrent())
    }
}
