import os

extension Logger {
    private static let subsystem = BuildConfig.loggingSubsystem

    static let app = Logger(subsystem: subsystem, category: "app")
    static let schedule = Logger(subsystem: subsystem, category: "schedule")
    static let healthkit = Logger(subsystem: subsystem, category: "healthkit")
    static let cloudkit = Logger(subsystem: subsystem, category: "cloudkit")
    static let parser = Logger(subsystem: subsystem, category: "parser")
    static let character = Logger(subsystem: subsystem, category: "character")
    static let api = Logger(subsystem: subsystem, category: "api")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let coach = Logger(subsystem: subsystem, category: "coach")
    static let wc = Logger(subsystem: subsystem, category: "wc")
}
