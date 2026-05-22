import Foundation
import SwiftData
import os

@MainActor
enum ProfileService {

    /// Returns the single canonical UserProfile, creating one if none exists.
    /// Single-user app: if multiple profiles exist (rare CloudKit edge case), returns the first.
    static func currentOrCreate(modelContext: ModelContext) -> UserProfile {
        let fetched = modelContext.fetchOrEmpty(FetchDescriptor<UserProfile>())
        if let existing = fetched.first {
            return existing
        }
        let new = UserProfile()
        modelContext.insert(new)
        do {
            try modelContext.save()
        } catch {
            Logger.persistence.error("Failed to save new UserProfile: \(error.localizedDescription, privacy: .public)")
        }
        return new
    }
}
