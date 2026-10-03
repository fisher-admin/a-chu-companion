import Foundation
import Translation

@main struct LanguageSmokeTests {
    @MainActor static func main() async throws {
        let chinese = Locale.Language(identifier: "zh-Hans")
        let availability = LanguageAvailability()
        var ready = true
        for language in TranslationLanguage.allCases {
            let other = Locale.Language(identifier: language.rawValue)
            let forward = await availability.status(from: chinese, to: other)
            let reverse = await availability.status(from: other, to: chinese)
            precondition(forward != .unsupported && reverse != .unsupported, "Requested language pair must be supported")
            print("\(language.name): forward=\(forward), reverse=\(reverse)")
            if CommandLine.arguments.contains("--availability-only") { continue }
            guard forward == .installed, reverse == .installed else { ready = false; continue }
            if #available(macOS 26.0, *) {
                let outgoing = TranslationSession(installedSource: chinese, target: other)
                let result = try await TextTranslation.run("请保留现有设置。") { try await outgoing.translate($0).targetText }
                precondition(!result.isEmpty && result != "请保留现有设置。")
                let incoming = TranslationSession(installedSource: other, target: chinese)
                let back = try await TextTranslation.run(result) { try await incoming.translate($0).targetText }
                precondition(back.contains("设置"))
                print("PASS: \(language.name) actual round trip: \(result) -> \(back)")
            } else { ready = false }
        }
        if ready && CommandLine.arguments.contains("--long"), #available(macOS 26.0, *) {
            let source = String(repeating: "Please keep the existing settings.\n", count: 1_400) + "Final marker: COMPLETE-49K-END."
            let session = TranslationSession(installedSource: .init(identifier: "en"), target: chinese)
            try ForeignTextPolicy.validate(source, incoming: true)
            let translated = try await TextTranslation.run(source, progress: { part, total in
                if part == 1 || part.isMultiple(of: 10) || part == total { print("Long reply: \(part)/\(total)"); fflush(stdout) }
            }) { try await session.translate($0).targetText }
            try translated.write(toFile: ".build/system-long-result.txt", atomically: true, encoding: .utf8)
            print("Long metrics: settings=\(translated.components(separatedBy: "设置").count - 1), length=\(translated.count), tail=\(translated.suffix(200))")
            precondition(translated.components(separatedBy: "设置").count - 1 == 1_400 && translated.suffix(100).contains("49K") && (translated.suffix(100).contains("标记") || translated.suffix(100).contains("marker")), "The complete long reply must retain every paragraph and its final marker")
            print("PASS: actual system translation of \(source.count) characters preserves all 1,400 paragraphs and the final marker")
        }
        guard ready else { print("Prepare missing language packs in the application before full verification"); exit(2) }
    }
}
