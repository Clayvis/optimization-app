# PERFORMANCE.md

Performance targets that must be met at every milestone close. Measured on real hardware where specified, simulator otherwise. Failure to meet a target is a Quality Gate failure.

## Cold Start

| Target | Threshold |
|--------|-----------|
| iPhone cold start to TodayView render | <1.5s |
| iPhone cold start to interactive | <2.0s |
| Watch cold start to current block visible | <2.0s |
| Watch complication initial render | <500ms |

Measure with Instruments (Time Profiler + App Launch template) on iPhone 16 Pro and Apple Watch Ultra 2 hardware.

## Hot Path Operations

| Operation | Threshold |
|-----------|-----------|
| Schedule resolution `currentBlock(at: Date)` | <50ms |
| Fast window state computation | <20ms |
| Hydration target lookup by day-of-week | <10ms |
| Streak calculation across 365-day window | <20ms |
| PhenoAge calculation | <10ms |
| Pattern detection (12 rules) | <50ms |
| Character state recompute | <30ms |
| Watch tap-to-log confirmation haptic | <200ms |

## Long-Running Operations

| Operation | Threshold |
|-----------|-----------|
| PDF parse end-to-end (DOD, 2 pages, text) | <30s |
| PDF parse end-to-end (scanned, OCR fallback) | <90s |
| Anthropic API call (Sonnet 4.6, 2k token response) | <10s |
| Weekly review generation | <500ms |
| HealthKit historical pull (90-day RHR + HRV + sleep) | <2s |
| CloudKit initial sync after fresh install | <30s |
| JSON export of full database | <5s |
| JSON import of full database | <10s |

## Memory

| Target | Threshold |
|--------|-----------|
| Phone app memory baseline (TodayView open) | <50 MB |
| Phone peak memory (PDF parse with OCR) | <250 MB |
| Phone peak memory (Anthropic API call active) | <100 MB |
| Watch app memory baseline | <30 MB |
| Watch app peak memory (workout active) | <80 MB |
| 8 mascot PNG assets bundle size | <8 MB |
| Total app bundle size | <50 MB |

Measure with Instruments (Allocations).

## Battery

| Target | Threshold |
|--------|-----------|
| Watch additional battery drain (12 hrs normal use) | <5% |
| Watch additional battery drain with always-on complication | <8% |
| Watch additional battery drain with active workout (4 hrs) | <15% |
| Watch additional battery drain with mascot complication | <1%/12hr |

Measure with Energy Log (Settings → Battery → Battery Health).

## Network

| Target | Threshold |
|--------|-----------|
| App total network usage in offline mode | 0 bytes |
| Anthropic API request size (PDF parse) | <2 MB upload |
| Anthropic API request size (analysis call) | <50 KB upload |
| CloudKit sync chunk size | OS-managed |

App must be fully functional with airplane mode on, except for Anthropic API features.

## Frame Rate

| Surface | Target |
|---------|--------|
| TodayView scrolling | 120fps on ProMotion devices, 60fps minimum |
| Trend charts during pan/zoom | 60fps |
| Mascot breathing animation | 60fps maintained continuously |
| Mascot state transition cross-fade | 60fps |
| Watch view transitions | 60fps |
| Watch complication updates | OS-budgeted |

Measure with Instruments (Animation Hitches template).

## Disk I/O

| Target | Threshold |
|--------|-----------|
| SwiftData write (single entity) | <50ms |
| SwiftData fetch (1000 records) | <100ms |
| Asset Catalog image load (mascot PNG) | <10ms (decoded), cached after first load |

## CloudKit

| Target | Threshold |
|--------|-----------|
| Sync latency phone-to-watch on local network | <30s |
| Sync latency phone-to-watch on cellular | <120s |
| Conflict rate per 100 modifications | <1 |

## Concurrency Safety

- All UI updates on @MainActor.
- Background work isolated to actors.
- No data races detected by Swift 6 strict concurrency checking at compile time.
- No `Task { @MainActor in ... }` wrapper antipatterns. Mark types correctly upfront.

## Background Tasks

- HealthKit observers: register at app launch, run in background.
- Background app refresh: opportunistic, never required.
- BGTaskScheduler: not used in v1 (no critical background work).

## Performance Testing Infrastructure

In `PersonalOptimizationTests/PerformanceTests.swift`:

```swift
import XCTest

final class PerformanceTests: XCTestCase {
    func testScheduleResolutionUnder50ms() {
        let service = ScheduleService.shared
        measure {
            for _ in 0..<100 {
                _ = service.currentBlock(at: Date())
            }
        }
    }

    func testPhenoAgeCalculationUnder10ms() {
        let values: [String: Double] = [/* 9 required markers */]
        measure {
            for _ in 0..<100 {
                _ = PhenoAge.calculate(values: values, age: 31.5)
            }
        }
    }

    func testPatternDetectionUnder50ms() {
        let values: [String: Double] = [/* full panel */]
        measure {
            _ = PatternDetection.detect(values: values, sex: "male")
        }
    }

    // ... one performance test per benchmark
}
```

XCTest's `measure` baseline-compares against last run. Set baselines at M1 close on real hardware.

## Profiling Cadence

- After every milestone, run Instruments for 5 minutes of typical usage.
- Record: app launch, navigate to TodayView, log water, start workout, view trends.
- Compare against previous milestone baseline. If any metric regressed >10%, investigate before merging.

## Watch Optimization Specifics

- Avoid heavy SwiftUI views on watchOS. Use simple shapes and text.
- Defer non-critical work to phone (analysis, weekly review generation).
- Use `Image(systemName:)` (SF Symbols) over custom images where possible.
- Mascot complication renders the asset PNG at 100x100pt max on watch (not 200x200pt like phone).
- Always-on display: use `.privacySensitive(false)` only on data already glanceable.
- Reduce timer fidelity in always-on: 1Hz updates, not 60Hz.
- Use `WKApplicationRefreshBackgroundTask` only for fast countdown updates, max once per minute.

## App Store Performance Metrics

After v1.0, monitor in App Store Connect:

- Crash rate: target <0.1% of sessions.
- Hang rate: target <0.5% of sessions.
- Disk write rate: target <500 KB/min average.
- Energy use: target green rating across all categories.

These map to MetricKit data collected via `MXMetricManager`.

## Regression Prevention

- Performance tests run in CI on every PR.
- Threshold breaches fail the PR.
- Improvement opportunities tracked in `.work/performance/improvements.md` for future milestones.
