import AppKit

/// The mounted disk image this copy of Konnyaku was installed from. After
/// Konnyaku launches from Applications, it offers once to eject the disk and
/// move the downloaded DMG to the Trash.
struct Installer {
    let image: URL
    let volume: URL
    /// The DMG's file identity when it was matched. Cleanup checks it again so
    /// a different file at the same path is never trashed.
    let identity: NSObject

    private static let bundleIdentifier = "io.github.yukinoda.konnyaku"
    private static let offeredKey = "installer.lastCleanupOffer"
    private static let infoPath = "Contents/Info.plist"
    private static let executablePath = "Contents/MacOS/Konnyaku"

    /// One check, off the main thread. Does nothing unless the running app is
    /// in /Applications or ~/Applications.
    static func offerCleanup() {
        let app = Bundle.main.bundleURL
        guard isInApplications(app) else {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            guard let installer = mounted(for: app) else {
                return
            }
            DispatchQueue.main.async {
                installer.offer()
            }
        }
    }

    static func isInApplications(
        _ app: URL,
        directories: [URL] = FileManager.default.urls(
            for: .applicationDirectory,
            in: [.localDomainMask, .userDomainMask]
        )
    ) -> Bool {
        let parent = app.resolvingSymlinksInPath().deletingLastPathComponent()
        return directories.contains { $0.resolvingSymlinksInPath() == parent }
    }

    /// Finds a mounted DMG whose volume holds the same build of Konnyaku as
    /// `app`. `images` is the "images" array from `hdiutil info -plist`.
    static func find(for app: URL, images: [[String: Any]]) -> Installer? {
        guard let installed = NSDictionary(contentsOf: app.appendingPathComponent(infoPath)) else {
            return nil
        }
        guard installed["CFBundleIdentifier"] as? String == bundleIdentifier else {
            return nil
        }
        guard let version = installed["CFBundleShortVersionString"] as? String else {
            return nil
        }

        for entry in images {
            guard let path = entry["image-path"] as? String else {
                continue
            }
            guard let entities = entry["system-entities"] as? [[String: Any]] else {
                continue
            }
            let image = URL(fileURLWithPath: path)
            guard image.pathExtension.lowercased() == "dmg" else {
                continue
            }
            // Match the volume before touching the DMG, so Konnyaku only
            // reads the download folder when its installer is mounted.
            let mountPoints = entities.compactMap { $0["mount-point"] as? String }
            let volumes = mountPoints.map { URL(fileURLWithPath: $0) }
            let match = volumes.first { volume in
                let source = volume.appendingPathComponent("Konnyaku.app")
                return isSameBuild(source, as: app, version: version)
            }
            guard let volume = match else {
                continue
            }

            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileResourceIdentifierKey]
            guard let attributes = try? image.resourceValues(forKeys: keys) else {
                continue
            }
            guard attributes.isRegularFile == true else {
                continue
            }
            guard let identity = attributes.fileResourceIdentifier as? NSObject else {
                continue
            }
            return Installer(image: image, volume: volume, identity: identity)
        }
        return nil
    }

    private static func isSameBuild(_ source: URL, as app: URL, version: String) -> Bool {
        guard let info = NSDictionary(contentsOf: source.appendingPathComponent(infoPath)) else {
            return false
        }
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier else {
            return false
        }
        guard info["CFBundleShortVersionString"] as? String == version else {
            return false
        }
        let installedExecutable = app.appendingPathComponent(executablePath).path
        let sourceExecutable = source.appendingPathComponent(executablePath).path
        return FileManager.default.contentsEqual(atPath: installedExecutable, andPath: sourceExecutable)
    }

    static func mounted(for app: URL) -> Installer? {
        guard let data = run("/usr/bin/hdiutil", ["info", "-plist"]) else {
            return nil
        }
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        guard let info = plist as? [String: Any] else {
            return nil
        }
        guard let images = info["images"] as? [[String: Any]] else {
            return nil
        }
        // Skip a DMG that was already offered before reading anything from it.
        let offered = UserDefaults.standard.string(forKey: offeredKey)
        let notOffered = images.filter { $0["image-path"] as? String != offered }
        return find(for: app, images: notOffered)
    }

    /// Runs a command-line tool and returns its output, or nil if it fails.
    private static func run(_ tool: String, _ arguments: [String]) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        return data
    }

    func imageIsCurrent() -> Bool {
        var file = image
        file.removeAllCachedResourceValues()
        guard let attributes = try? file.resourceValues(forKeys: [.fileResourceIdentifierKey]) else {
            return false
        }
        guard let current = attributes.fileResourceIdentifier as? NSObject else {
            return false
        }
        return identity.isEqual(current)
    }

    /// Ejects the disk, then moves the DMG to the Trash. Never trashes the
    /// file if the eject fails or the file was replaced.
    func remove(completion: @escaping (Error?) -> Void) {
        let changed = CocoaError(.fileReadUnknown, userInfo: [
            NSLocalizedDescriptionKey: "The downloaded disk image changed after Konnyaku found it.",
        ])
        let ejectFailed = CocoaError(.fileWriteUnknown, userInfo: [
            NSLocalizedDescriptionKey: "The installer disk couldn't be ejected.",
        ])
        DispatchQueue.global(qos: .utility).async {
            guard imageIsCurrent() else {
                completion(changed)
                return
            }
            // Not NSWorkspace.unmountAndEjectDevice: on an APFS image it
            // unmounts the volume but leaves the image attached.
            guard Self.run("/usr/sbin/diskutil", ["eject", volume.path]) != nil else {
                completion(ejectFailed)
                return
            }
            guard imageIsCurrent() else {
                completion(changed)
                return
            }
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle([image]) { moved, error in
                    if moved[image] != nil {
                        completion(nil)
                    } else {
                        completion(error ?? CocoaError(.fileWriteUnknown))
                    }
                }
            }
        }
    }

    private func offer() {
        UserDefaults.standard.set(image.path, forKey: Self.offeredKey)

        let alert = NSAlert()
        alert.messageText = "Konnyaku is installed"
        alert.informativeText = "You can eject the installer disk and move "
            + "“\(image.lastPathComponent)” to the Trash. "
            + "Konnyaku stays in Applications."
        alert.addButton(withTitle: "Keep Installer")
        alert.addButton(withTitle: "Eject & Move to Trash")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else {
            return
        }
        remove { error in
            guard let error else {
                return
            }
            DispatchQueue.main.async {
                Self.showFailure(error)
            }
        }
    }

    private static func showFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't remove the installer"
        alert.informativeText = error.localizedDescription
            + " Konnyaku is still installed. You can finish removing the installer in Finder."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
