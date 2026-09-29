import Foundation
import Translation

@main struct TranslationSmokeTests {
    static func main() async throws {
        if #available(macOS 26.0, *) {
            let english = Locale.Language(identifier: "en")
            let chinese = Locale.Language(identifier: "zh-Hans")
            let available = await LanguageAvailability().status(from: english, to: chinese)
            guard available == .installed else {
                print("Language packs not installed"); exit(2)
            }
            let session = TranslationSession(installedSource: english, target: chinese)
            let result = try await session.translate("Please keep the existing settings. Restart the application after saving your work.")
            guard !result.targetText.isEmpty && result.targetText != result.sourceText else { exit(1) }
            print("English to Chinese: \(result.targetText)")
            print("PASS: installed system reverse translation")
        } else { print("Requires macOS 26"); exit(2) }
    }
}
