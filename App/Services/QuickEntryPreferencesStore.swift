import Foundation

@MainActor enum QuickEntryPreferencesStore {
    private static let key = "quick-entry.preferences.v1"

    static func load(defaults: UserDefaults? = nil) -> QuickEntryPreferences? {
        guard defaults != nil || !RuntimeMode.isEphemeral,
              let data = (defaults ?? .standard).data(forKey: key),
              let preferences = try? JSONDecoder().decode(QuickEntryPreferences.self, from: data),
              SpendCategory(rawValue: preferences.category) != nil,
              PaymentMethod(rawValue: preferences.paymentMethod) != nil else { return nil }
        return preferences
    }

    static func save(_ preferences: QuickEntryPreferences, defaults: UserDefaults? = nil) {
        guard defaults != nil || !RuntimeMode.isEphemeral,
              let data = try? JSONEncoder().encode(preferences) else { return }
        (defaults ?? .standard).set(data, forKey: key)
    }
}
