import Foundation
import SwiftData
import os

/// Fail-soft SwiftData helpers. CLAUDE.md requires every `try?` to carry
/// a justification comment, and the vast majority of read-path `try?`
/// calls in this codebase share the same justification: a SwiftData
/// fetch failure is an in-process store-corruption signal that the user
/// can't act on inline, and a nil result is semantically equivalent to
/// an empty result at the call site.
///
/// These helpers encode that justification once. Callers replace
/// `(try? ctx.fetch(d)) ?? []` with `ctx.fetchOrEmpty(d)` and
/// `(try? ctx.fetch(d))?.first` with `ctx.fetchFirstOrNil(d)`. Every
/// caught failure is logged with the call site so production diagnostics
/// surface real persistence issues instead of swallowing them.
extension ModelContext {

    /// Fail-soft fetch. Returns an empty array if the descriptor throws.
    /// Failures are logged via `Logger.persistence` with the call site.
    func fetchOrEmpty<T>(_ descriptor: FetchDescriptor<T>,
                          file: String = #fileID,
                          line: Int = #line) -> [T] where T: PersistentModel {
        do {
            return try fetch(descriptor)
        } catch {
            Logger.persistence.error("fetchOrEmpty failed at \(file, privacy: .public):\(line, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fail-soft single-result fetch. Returns nil on error or no rows.
    /// Failures are logged via `Logger.persistence` with the call site.
    func fetchFirstOrNil<T>(_ descriptor: FetchDescriptor<T>,
                             file: String = #fileID,
                             line: Int = #line) -> T? where T: PersistentModel {
        do {
            return try fetch(descriptor).first
        } catch {
            Logger.persistence.error("fetchFirstOrNil failed at \(file, privacy: .public):\(line, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Fail-soft count fetch. Returns 0 on error.
    func fetchCountOrZero<T>(_ descriptor: FetchDescriptor<T>,
                              file: String = #fileID,
                              line: Int = #line) -> Int where T: PersistentModel {
        do {
            return try fetchCount(descriptor)
        } catch {
            Logger.persistence.error("fetchCountOrZero failed at \(file, privacy: .public):\(line, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return 0
        }
    }
}
