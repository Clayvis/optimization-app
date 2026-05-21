import AppIntents

struct PersonalOptimizationShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCurrentBlockWorkoutIntent(),
            phrases: [
                "Start workout in \(.applicationName)",
                "Start my current block in \(.applicationName)",
                "\(.applicationName) start training"
            ],
            shortTitle: "Start Workout",
            systemImageName: "figure.run"
        )
        AppShortcut(
            intent: LogHydrationIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Log hydration in \(.applicationName)",
                "\(.applicationName) log water"
            ],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: StartFastIntent(),
            phrases: [
                "Start a fast in \(.applicationName)",
                "\(.applicationName) start fast"
            ],
            shortTitle: "Start Fast",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: EndFastIntent(),
            phrases: [
                "End my fast in \(.applicationName)",
                "\(.applicationName) end fast"
            ],
            shortTitle: "End Fast",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: LogLearningIntent(),
            phrases: [
                "Log learning in \(.applicationName)",
                "\(.applicationName) log study"
            ],
            shortTitle: "Log Learning",
            systemImageName: "book.fill"
        )
        #if os(iOS)
        AppShortcut(
            intent: TellCoachIntent(),
            phrases: [
                "Tell my coach in \(.applicationName)",
                "\(.applicationName) tell coach"
            ],
            shortTitle: "Tell Coach",
            systemImageName: "text.bubble.fill"
        )
        #endif
    }
}
