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
    }
}
