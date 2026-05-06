# SECURITY.md

Privacy, security, and data handling rules. Mandatory at every milestone. Failure means Quality Gate failure.

## Threat Model

Single-user personal app. Threats considered:

1. Device loss or theft. Mitigated by iOS device passcode and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for Keychain items.
2. Malicious dependencies. Mitigated by zero third-party packages.
3. Network intercept. Mitigated by HTTPS-only network calls (Anthropic API), App Transport Security enforced.
4. Cloud data exposure. Mitigated by CloudKit private database (encrypted at rest, scoped to user's iCloud).
5. Lab PDF data leakage. Mitigated by storing PDFs only locally; sent to Anthropic only on explicit user tap.
6. Crash dumps with PII. Mitigated by OSLogPrivacy attributes on user data in logs.

Threats explicitly NOT in scope:

- Multi-user attacks (single-user app).
- Server-side breach (no server).
- Account takeover (no accounts).
- Marketing data leakage (no marketing SDKs).

## Data Classification

| Data type | Sensitivity | Storage | Sync |
|-----------|-------------|---------|------|
| Profile (name, DOB, sex, height, weight) | Personal | SwiftData | iCloud Private |
| Schedule blocks | Low | SwiftData | iCloud Private |
| Daily logs (water, fast, energy) | Medium | SwiftData | iCloud Private |
| Workout data | Medium | SwiftData + HealthKit | iCloud Private + Health (user controls) |
| Biomarker values | High (medical) | SwiftData | iCloud Private |
| Lab PDF source files | High (medical) | App Documents directory | NOT synced |
| Anthropic API key | Critical | Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) | NOT synced |
| Character state log | Low | SwiftData | iCloud Private |

## Keychain Service

`Services/KeychainService.swift`:

```swift
import Foundation
import Security
import os

enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound: return "Item not found in Keychain"
        case .duplicateItem: return "Item already exists in Keychain"
        case .unexpectedStatus(let status): return "Keychain operation failed: \(status)"
        }
    }
}

final class KeychainService {
    static let shared = KeychainService()
    private let logger = Logger.api

    private let service = "com.<YOUR-TEAM>.PersonalOptimization"

    func setApiKey(_ key: String) throws {
        try set(key: "anthropic_api_key", value: key)
    }

    func getApiKey() throws -> String {
        try get(key: "anthropic_api_key")
    }

    func deleteApiKey() throws {
        try delete(key: "anthropic_api_key")
    }

    // Generic methods
    private func set(key: String, value: String) throws {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary) // Delete existing
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain set failed: \(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func get(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }
        return value
    }

    private func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

Implementation rules:
- API key NEVER logged.
- API key NEVER written to UserDefaults, plist, or JSON export.
- API key NEVER printed to console even in debug builds.
- API key access uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (no iCloud Keychain sync).
- Tests for KeychainService run on simulator only (Keychain available there).

## Privacy Manifest

`PrivacyInfo.xcprivacy` required from M1. Contents:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeHealthFitness</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>35F9.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryDiskSpace</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>E174.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

Update at each milestone that adds new data access:
- M2: NSHealthShareUsageDescription, NSHealthUpdateUsageDescription added.
- M3: Workout types added to HealthKit reasons.
- M5: Network usage added (Anthropic API).
- M6: Widget data declarations.

## Info.plist Usage Descriptions

All required from M1 forward:

```xml
<key>NSHealthShareUsageDescription</key>
<string>Tracks sleep, heart rate, and HRV to power character emotional state and weekly review insights.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Logs workouts and water intake to Apple Health for cross-app integration.</string>

<key>NSUserNotificationUsageDescription</key>
<string>Sends reminders for hydration, fast transitions, and scheduled blocks.</string>
```

No camera, no photo library, no contacts, no location in v1.

## App Transport Security

Default ATS policy enforced. No exceptions. No `NSAllowsArbitraryLoads`. Only HTTPS connections allowed. Anthropic API uses HTTPS by default.

## Data Export and Deletion

JSON export from Settings includes ALL SwiftData entities. Excludes:
- Anthropic API key (in Keychain, not SwiftData).
- Source PDF files (in Documents directory, not SwiftData).

JSON export structure:

```json
{
  "version": 1,
  "exportedAt": "2026-05-05T12:00:00Z",
  "userProfile": { ... },
  "scheduleBlocks": [ ... ],
  "dailyLogs": [ ... ],
  ...
}
```

Delete-all-data flow in Settings:
1. Confirm with two-step prompt.
2. Delete all SwiftData entities.
3. Delete all PDF files in Documents directory.
4. Delete API key from Keychain.
5. Restart app.

## Logging Privacy

Use `os.Logger` with privacy attributes:

```swift
Logger.parser.info("Parsed \(count, privacy: .public) markers from \(filename, privacy: .private)")
Logger.api.info("API call to \(endpoint, privacy: .public) returned status \(status, privacy: .public)")
Logger.api.error("API key set (length: \(key.count, privacy: .public))")  // never log key itself
```

Default to `.private` for any user-supplied data. Use `.public` only for system metadata (status codes, counts, durations).

## CloudKit Container

- Private database only. No public, no shared.
- Container ID: `iCloud.com.<YOUR-TEAM>.PersonalOptimization`.
- All records stored in user's iCloud, encrypted at rest by Apple.
- App reads CloudKit account status at launch; if signed out of iCloud, app works locally without sync.

## Anthropic API Calls

Rules:

1. Only on explicit user tap of "Parse with Claude" or "Ask Claude (live)" buttons.
2. Show user a confirmation dialog first time per session: "This sends your lab data to Anthropic for analysis. The data is not retained per Anthropic's API privacy policy. Proceed?"
3. Network call uses HTTPS to `api.anthropic.com`.
4. Request includes `anthropic-version: 2023-06-01` header.
5. API key from Keychain, never hardcoded.
6. Response logged at INFO level with response length only, never response body.
7. PDF base64 data NEVER logged.

## App Group

`group.com.<YOUR-TEAM>.PersonalOptimization` shared between iOS app, watchOS app, Widget extension, Live Activity extension.

Used for:
- Sharing UserDefaults (preferences).
- Shared file containers if needed.
- NOT for sharing API key (Keychain has its own access group).

## Crash Reporting

Use Apple's MetricKit framework for crash data. No third-party crash reporting (Crashlytics, Sentry, etc.).

```swift
import MetricKit

final class MetricsService: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsService()

    func register() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // Process metrics, optionally write to local log
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Process crash and hang reports
    }
}
```

## Test Doubles for Security-Sensitive Code

KeychainService tests use simulator's Keychain (works without code signing).

Anthropic API tests mock URLSession via `URLProtocol` swizzling pattern (no third-party mock framework needed).

## Pre-Release Checklist

Before shipping any TestFlight build:

- [ ] All Info.plist usage descriptions present.
- [ ] PrivacyInfo.xcprivacy declares all data types and APIs.
- [ ] No third-party SDKs added.
- [ ] No `print()` statements in production code (use Logger).
- [ ] No API keys, tokens, or secrets in source code.
- [ ] No CloudKit public database access.
- [ ] App Transport Security: no exceptions.
- [ ] Encryption export compliance: `ITSAppUsesNonExemptEncryption` set to false (only standard encryption used).

## Security Review Cadence

- Per milestone: agent re-reads SECURITY.md before closing.
- Per release: full checklist above.
- Annual: review entire app for new platform security requirements.
