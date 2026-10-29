import Foundation
import Testing
@testable import FootprintCore

/// Measures throwaway folders only, never anything of yours.
@Suite("Disk use")
struct DiskTests {
    let scanner = DiskScanner()

    @Test func aMissingFolderIsNil() {
        #expect(scanner.usage(of: scratchFolder().appendingPathComponent("nope")) == nil)
    }

    @Test func anEmptyFolder() throws {
        let usage = try #require(scanner.usage(of: scratchFolder()))
        #expect(usage.files == 0)
        #expect(usage.parts.isEmpty)
    }

    @Test func addsUpFilesInSubfolders() throws {
        let root = scratchFolder()
        try write(300_000, to: root.appendingPathComponent("models/a.bin"))
        try write(200_000, to: root.appendingPathComponent("models/deep/b.bin"))
        try write(50_000, to: root.appendingPathComponent("logs/today.log"))
        let usage = try #require(scanner.usage(of: root))
        #expect(usage.files == 3)
        #expect(usage.bytes >= 550_000)
        // Space on disk rounds up to whole blocks, but not by much.
        #expect(usage.bytes < 700_000)
    }

    @Test func namesTheBiggestPartsFirst() throws {
        let root = scratchFolder()
        try write(400_000, to: root.appendingPathComponent("models/a.bin"))
        try write(100_000, to: root.appendingPathComponent("logs/a.log"))
        try write(10_000, to: root.appendingPathComponent("config.json"))
        let usage = try #require(scanner.usage(of: root))
        #expect(usage.parts.map(\.name) == ["models", "logs", "config.json"])
        #expect(usage.parts[0].bytes >= 400_000)
    }

    @Test func keepsOnlyAFewParts() throws {
        let root = scratchFolder()
        for index in 0..<7 {
            try write(10_000 * (index + 1), to: root.appendingPathComponent("part\(index)/file"))
        }
        let usage = try #require(scanner.usage(of: root))
        #expect(usage.parts.count == Usage.partLimit)
        #expect(usage.parts.first?.name == "part6")
    }

    @Test func doesntFollowSymbolicLinks() throws {
        let root = scratchFolder()
        let elsewhere = scratchFolder()
        try write(500_000, to: elsewhere.appendingPathComponent("big.bin"))
        try write(10_000, to: root.appendingPathComponent("small.bin"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: elsewhere)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("file-link"), withDestinationURL: elsewhere.appendingPathComponent("big.bin"))
        let usage = try #require(scanner.usage(of: root))
        #expect(usage.bytes < 100_000)
        #expect(usage.files == 1)
    }

    @Test func countsHardLinksOnce() throws {
        let root = scratchFolder()
        let original = root.appendingPathComponent("blobs/model.bin")
        try write(400_000, to: original)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("snapshots"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("snapshots/model.bin"))
        let usage = try #require(scanner.usage(of: root))
        #expect(usage.files == 1)
        #expect(usage.bytes < 600_000)
    }

    @Test func aSingleFile() throws {
        let file = scratchFolder().appendingPathComponent("history.jsonl")
        try write(120_000, to: file)
        let usage = try #require(scanner.usage(of: file))
        #expect(usage.files == 1)
        #expect(usage.bytes >= 120_000)
        #expect(usage.parts.isEmpty)
        #expect(usage.modified != nil)
    }

    @Test func remembersTheNewestChange() throws {
        let root = scratchFolder()
        let old = root.appendingPathComponent("old.log")
        let new = root.appendingPathComponent("sub/new.log")
        try write(1000, to: old)
        try write(1000, to: new)
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: root.appendingPathComponent("sub").path)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: root.path)
        let usage = try #require(scanner.usage(of: root))
        let modified = try #require(usage.modified)
        #expect(modified > past.addingTimeInterval(1000))
    }

    @Test func stopsWhenCancelled() throws {
        let root = scratchFolder()
        try write(1000, to: root.appendingPathComponent("a"))
        #expect(scanner.usage(of: root, isCancelled: { true }) == nil)
    }

    @Test func unreadableFoldersAreSkipped() throws {
        let root = scratchFolder()
        let locked = root.appendingPathComponent("locked")
        try write(50_000, to: locked.appendingPathComponent("secret"))
        try write(20_000, to: root.appendingPathComponent("open"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let usage = try #require(scanner.usage(of: root))
        #expect(usage.files == 1)
    }
}
