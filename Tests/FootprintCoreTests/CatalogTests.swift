import Foundation
import Testing
@testable import FootprintCore

/// The app's entitlements and its list of folders have to agree: a folder the catalog names but
/// the entitlements leave out would always look empty, and one the entitlements allow but the
/// catalog doesn't use is access the app shouldn't have.
@Suite("Catalog")
struct CatalogTests {
    static let entitlementsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/AIFootprint.entitlements")

    private func entitlements() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.entitlementsURL)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func readOnlyPaths() throws -> [String] {
        try #require(entitlements()["com.apple.security.temporary-exception.files.home-relative-path.read-only"] as? [String])
    }

    @Test func entitlementsMatchTheCatalog() throws {
        let expected = Tool.all.flatMap(\.locations).map { "/" + $0.path + ($0.isFile ? "" : "/") }
            + Tool.launchAgentFolders.map { "/" + $0.path + "/" }
        #expect(try readOnlyPaths().sorted() == expected.sorted())
    }

    @Test func onlyTheSandboxAndReadOnlyFolders() throws {
        let keys = try Set(entitlements().keys)
        #expect(keys == ["com.apple.security.app-sandbox", "com.apple.security.temporary-exception.files.home-relative-path.read-only"])
        #expect(try entitlements()["com.apple.security.app-sandbox"] as? Bool == true)
    }

    @Test func noFolderHoldsSettingsOrKeys() throws {
        // Whole tool folders would include sign-in tokens and keys, so only named parts are allowed.
        let whole = ["/.claude/", "/.codex/", "/.ollama/", "/.lmstudio/", "/.cache/huggingface/", "/Library/Application Support/Claude/", "/.claude.json", "/"]
        for path in try readOnlyPaths() {
            #expect(!whole.contains(path), "\(path) is a whole tool folder")
            #expect(!path.contains("auth") && !path.contains("token") && !path.contains("id_ed25519") && !path.contains("config"), "\(path) holds secrets")
        }
    }

    @Test func pathsAreWellFormed() throws {
        for location in Tool.all.flatMap(\.locations) {
            #expect(!location.path.hasPrefix("/") && !location.path.hasPrefix("~"), "\(location.path) should be relative to home")
            #expect(!location.path.hasSuffix("/"))
            #expect(!location.path.contains(".."))
            #expect(!location.label.isEmpty)
        }
    }

    @Test func everyLocationBelongsToOneTool() {
        let paths = Tool.all.flatMap(\.locations).map(\.path)
        #expect(Set(paths).count == paths.count)
        // And none sits inside another, which would count its bytes twice.
        for path in paths {
            #expect(!paths.contains { $0 != path && path.hasPrefix($0 + "/") }, "\(path) is inside another location")
        }
    }

    @Test func toolIDsAreUnique() {
        #expect(Set(Tool.all.map(\.id)).count == Tool.all.count)
        #expect(Set(Tool.all.map(\.name)).count == Tool.all.count)
    }

    @Test func versionFoldersAreReadable() {
        let granted = Tool.all.flatMap(\.locations).map(\.path)
        for folder in Tool.all.flatMap(\.versionFolders) {
            #expect(granted.contains { folder == $0 || folder.hasPrefix($0 + "/") }, "\(folder) isn't in a readable location")
        }
    }

    @Test func symbolsExist() {
        #expect(Tool.all.allSatisfy { !$0.symbol.isEmpty })
    }
}
