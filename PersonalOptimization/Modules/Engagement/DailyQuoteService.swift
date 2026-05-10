import Foundation
import os

struct DailyQuote: Sendable, Equatable {
    let text: String
    let attribution: String?
    let style: String

    var displayText: String {
        if let a = attribution, !a.isEmpty {
            return "\"\(text)\" — \(a)"
        }
        return text
    }
}

/// Daily quote rotation. Curated DB by style is free and always available.
/// If `aiQuotesEnabled` is on the profile, the service may call Haiku for a
/// fresh, style-tuned quote (cached for the day).
@MainActor
final class DailyQuoteService {
    private let logger = Logger.coach
    private let api: CoachAPIInvoking
    private let now: () -> Date
    private var cache: [String: DailyQuote] = [:]   // dayKey-style => quote

    init(api: CoachAPIInvoking = LiveCoachAPI(), now: @escaping () -> Date = Date.init) {
        self.api = api
        self.now = now
    }

    /// Returns a deterministic curated quote for today based on style. Same call
    /// on the same day returns the same quote so the UI feels stable. Use
    /// `dailyQuoteFromAPI` separately if AI generation is enabled.
    func curatedQuote(style: String, customStylePrompt: String? = nil) -> DailyQuote {
        let resolved = resolveStyle(style: style)
        let pool = Self.curatedPool[resolved] ?? Self.curatedPool["balanced"] ?? []
        guard !pool.isEmpty else {
            return DailyQuote(text: "Show up. Get to work.", attribution: nil, style: resolved)
        }
        let dayKey = self.dayKey(now: now())
        let cacheKey = "\(dayKey)-\(resolved)"
        if let cached = cache[cacheKey] { return cached }

        // Hash dayKey + style to pick a stable index for the day.
        let seed = abs((dayKey + resolved).hash)
        let chosen = pool[seed % pool.count]
        let quote = DailyQuote(text: chosen.text, attribution: chosen.attribution, style: resolved)
        cache[cacheKey] = quote
        return quote
    }

    /// Calls Haiku for a fresh quote tuned to the user's style. Falls back to the
    /// curated quote on any error so the UI is never empty. Cached per day.
    func dailyQuote(style: String,
                    customStylePrompt: String?,
                    aiEnabled: Bool,
                    model: String = "claude-haiku-4-5-20251001") async -> DailyQuote {
        let curated = curatedQuote(style: style, customStylePrompt: customStylePrompt)
        guard aiEnabled else { return curated }

        let dayKey = self.dayKey(now: now())
        let cacheKey = "ai-\(dayKey)-\(style)"
        if let cached = cache[cacheKey] { return cached }

        let resolved = resolveStyle(style: style)
        let stylePrompt: String = {
            if style == "custom", let custom = customStylePrompt, !custom.isEmpty {
                return "custom: \(custom)"
            }
            return resolved
        }()
        let system = """
        You produce a single 1-sentence quote tuned to the user's style. No quote marks.
        No em dashes. No filler. Output the quote text only, optionally followed by " — Author"
        if you're citing one. Max 25 words.
        Style: \(stylePrompt).
        """
        let user = "Today's quote, please."

        do {
            let response = try await api.complete(
                model: model,
                systemPrompt: system,
                userPrompt: user,
                maxTokens: 64
            )
            let parsed = Self.parse(response.text, style: resolved)
            cache[cacheKey] = parsed
            return parsed
        } catch {
            logger.warning("AI quote fell back to curated: \(error.localizedDescription, privacy: .public)")
            return curated
        }
    }

    private func dayKey(now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let comps = cal.dateComponents([.year, .month, .day], from: now)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    private func resolveStyle(style: String) -> String {
        let valid: Set<String> = ["balanced", "stoic", "holistic", "warrior", "spiritual", "scientific"]
        return valid.contains(style) ? style : "balanced"
    }

    static func parse(_ text: String, style: String) -> DailyQuote {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dashRange = trimmed.range(of: " — ") ?? trimmed.range(of: " - ") {
            let body = String(trimmed[trimmed.startIndex..<dashRange.lowerBound])
            let author = String(trimmed[dashRange.upperBound..<trimmed.endIndex])
            return DailyQuote(text: body.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                              attribution: author.isEmpty ? nil : author,
                              style: style)
        }
        return DailyQuote(text: trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                          attribution: nil,
                          style: style)
    }
}

// MARK: - Curated pools

private struct CuratedQuote {
    let text: String
    let attribution: String?
}

extension DailyQuoteService {
    fileprivate static let curatedPool: [String: [CuratedQuote]] = [
        "stoic": [
            CuratedQuote(text: "You have power over your mind, not outside events. Realize this, and you will find strength.", attribution: "Marcus Aurelius"),
            CuratedQuote(text: "Waste no more time arguing what a good man should be. Be one.", attribution: "Marcus Aurelius"),
            CuratedQuote(text: "We suffer more often in imagination than in reality.", attribution: "Seneca"),
            CuratedQuote(text: "Difficulties strengthen the mind, as labor does the body.", attribution: "Seneca"),
            CuratedQuote(text: "It is not what happens to you, but how you react to it that matters.", attribution: "Epictetus"),
            CuratedQuote(text: "First say to yourself what you would be; and then do what you have to do.", attribution: "Epictetus"),
            CuratedQuote(text: "The impediment to action advances action. What stands in the way becomes the way.", attribution: "Marcus Aurelius"),
            CuratedQuote(text: "If it is not right, do not do it. If it is not true, do not say it.", attribution: "Marcus Aurelius"),
            CuratedQuote(text: "Begin at once to live, and count each separate day as a separate life.", attribution: "Seneca"),
            CuratedQuote(text: "No man is free who is not master of himself.", attribution: "Epictetus")
        ],
        "warrior": [
            CuratedQuote(text: "Discipline equals freedom.", attribution: "Jocko Willink"),
            CuratedQuote(text: "Either you run the day or the day runs you.", attribution: "Jim Rohn"),
            CuratedQuote(text: "It's supposed to be hard. The hard is what makes it great.", attribution: "Tom Hanks"),
            CuratedQuote(text: "Be water, my friend.", attribution: "Bruce Lee"),
            CuratedQuote(text: "The strong shall stand. The weak will fall by the wayside.", attribution: nil),
            CuratedQuote(text: "Pain is weakness leaving the body.", attribution: "USMC"),
            CuratedQuote(text: "When the time to perform arrives, the time to prepare has passed.", attribution: nil),
            CuratedQuote(text: "Embrace the suck. Move forward.", attribution: nil),
            CuratedQuote(text: "He who sweats more in training bleeds less in war.", attribution: "Spartan saying"),
            CuratedQuote(text: "Stay hard.", attribution: "David Goggins")
        ],
        "holistic": [
            CuratedQuote(text: "Breathe in, breathe out. The work is to be present.", attribution: nil),
            CuratedQuote(text: "Move with intention. Rest with purpose.", attribution: nil),
            CuratedQuote(text: "Your body is the vehicle. Take care of it.", attribution: nil),
            CuratedQuote(text: "Hydrate. Stretch. Sleep. The basics are advanced.", attribution: nil),
            CuratedQuote(text: "Slow is smooth. Smooth is fast.", attribution: nil),
            CuratedQuote(text: "Notice what you avoid. That's where the work is.", attribution: nil),
            CuratedQuote(text: "You don't need motivation. You need rhythm.", attribution: nil),
            CuratedQuote(text: "Effort is the bridge between intention and outcome.", attribution: nil),
            CuratedQuote(text: "Nothing is worth more than this day.", attribution: "Goethe"),
            CuratedQuote(text: "Walk slowly. Eat slowly. Live deliberately.", attribution: nil)
        ],
        "spiritual": [
            CuratedQuote(text: "Be thankful for this day. The morning is enough.", attribution: nil),
            CuratedQuote(text: "Let what is essential be essential.", attribution: nil),
            CuratedQuote(text: "Stillness is the master of motion.", attribution: "Lao Tzu"),
            CuratedQuote(text: "When the student is ready, the teacher appears.", attribution: nil),
            CuratedQuote(text: "Do the work that is in front of you, with full attention.", attribution: nil),
            CuratedQuote(text: "Faith is taking the first step even when you don't see the staircase.", attribution: "MLK Jr."),
            CuratedQuote(text: "The cave you fear holds the treasure you seek.", attribution: "Joseph Campbell"),
            CuratedQuote(text: "Light a candle, do not curse the darkness.", attribution: nil),
            CuratedQuote(text: "Less head. More heart.", attribution: nil),
            CuratedQuote(text: "Today is a gift. The work is to receive it.", attribution: nil)
        ],
        "scientific": [
            CuratedQuote(text: "Sleep loss reduces glucose tolerance and increases cortisol within one night.", attribution: nil),
            CuratedQuote(text: "Resistance training preserves mitochondrial density into the seventh decade.", attribution: nil),
            CuratedQuote(text: "16:8 fasting elevates autophagy markers without measurable muscle loss.", attribution: nil),
            CuratedQuote(text: "Zone 2 cardio raises mitochondrial efficiency more than HIIT alone.", attribution: nil),
            CuratedQuote(text: "Hydration at 2.5% body weight loss already reduces cognitive performance.", attribution: nil),
            CuratedQuote(text: "VO2 max is the single best predictor of all-cause mortality.", attribution: nil),
            CuratedQuote(text: "HRV is most informative as a 7-day rolling average, not a daily reading.", attribution: nil),
            CuratedQuote(text: "Strength training reduces all-cause mortality more than cardio at equal volume.", attribution: nil),
            CuratedQuote(text: "Caffeine half-life is six hours. Cutoff at noon to protect sleep architecture.", attribution: nil),
            CuratedQuote(text: "Cold exposure of 11 minutes per week elevates norepinephrine for hours.", attribution: nil)
        ],
        "balanced": [
            CuratedQuote(text: "Win the morning. The day takes care of itself.", attribution: nil),
            CuratedQuote(text: "Consistency beats intensity. Every time.", attribution: nil),
            CuratedQuote(text: "Show up. Sweat. Rest. Repeat.", attribution: nil),
            CuratedQuote(text: "Small reps add up faster than big plans.", attribution: nil),
            CuratedQuote(text: "Be the kind of athlete who logs the easy day.", attribution: nil),
            CuratedQuote(text: "What gets measured gets done.", attribution: "Peter Drucker"),
            CuratedQuote(text: "The body keeps the score. Be honest with it.", attribution: nil),
            CuratedQuote(text: "Train the system, not the day.", attribution: nil),
            CuratedQuote(text: "Today, just do today.", attribution: nil),
            CuratedQuote(text: "Boring is sustainable. Sustainable wins.", attribution: nil)
        ]
    ]
}
