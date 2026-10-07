import Foundation

@main struct StructureEdgeTests {
    @MainActor static func main() async throws {
        let text = "Translate around ``literal `backtick` code`` please."
        let result = try await TextTranslation.runProtected(text) { $0.uppercased() }
        precondition(result.contains("``literal `backtick` code``"))
        print("PASS: variable-width inline code fences retain embedded backticks exactly")
        print("1 structure edge contract passed")
    }
}
