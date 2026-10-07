import Foundation

enum CompanionPreferences {
    static let simulated = ProcessInfo.processInfo.arguments.contains("--simulation")
    static let store: UserDefaults = simulated ? UserDefaults(suiteName: "local.achu.simulation.preferences")! : .standard
}
