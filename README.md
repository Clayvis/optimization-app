# Optimization App

Native iOS 18+ and watchOS 11+ app for daily protocol tracking. Single user. Zero servers, zero accounts, zero third-party Swift packages.

Built with Claude Code following the documents in this folder. The whole package is designed to be paste-into-Claude-Code-and-go.

## Quick Start

```bash
# 1. Move to projects directory and init git
mv ~/Downloads/optimization-app ~/projects/optimization-app
cd ~/projects/optimization-app
git init && git add . && git commit -m "Initial package"
gh repo create optimization-app --private --source=. --remote=origin
git push -u origin main

# 2. Verify prerequisites
node --version       # 18+
claude --version     # Claude Code installed
xcode-select -p      # Xcode CLI tools installed
gh --version         # GitHub CLI authenticated

# 3. Confirm Claude Code permissions in ~/.claude/settings.json (see BOOTSTRAP.md)

# 4. Launch Claude Code
claude
```

Then open `BOOTSTRAP.md`, copy the entire fenced block, paste as your first message.

## Files in This Package

| File | Purpose |
|------|---------|
| `README.md` | This file, entry point |
| `BOOTSTRAP.md` | Paste-ready first message for Claude Code |
| `CLAUDE.md` | Persistent project context, loaded every session |
| `PROJECT_BRIEF.md` | What we are building, why, success criteria |
| `ARCHITECTURE.md` | Locked tech decisions |
| `DATA_MODELS.md` | All 13 SwiftData @Model specifications |
| `MILESTONES.md` | M1 through M7 with full Definition of Done |
| `PERFORMANCE.md` | Performance targets, battery, memory, network |
| `TESTING.md` | Test strategy and coverage targets |
| `SECURITY.md` | Privacy, Keychain, data handling |
| `.gitignore` | Xcode/Swift/macOS exclusions |
| `References/biomarker-tracker.html` | Validated biomarker logic (used at M5) |
| `References/default_schedule.json` | Schedule seed data (used at M1) |
| `References/sample_lab_dod.json` | Parser regression target (used at M5) |
| `References/character_brief.md` | Mascot aesthetic and 8-state spec (used at M6.5) |
| `References/gemini_workflow.md` | Step-by-step Gemini web prompts for character art (used at M6.5) |

## Apple Developer Account

Free personal team works for simulator and 7-day device installs. Paid Apple Developer Program ($99/year) required for HealthKit background delivery, push notifications, and TestFlight. Decide before M7. BOOTSTRAP.md asks Claude Code to confirm your status during bootstrap.

## Bundle ID Placeholder

Bundle identifier uses `<YOUR-TEAM>` as a placeholder throughout the package. Claude Code will prompt for your reverse-domain identifier during bootstrap (e.g., `com.clayrawlins`) and replace all occurrences before the first build.

## Estimated Effort

100-134 hours of Claude Code execution across 8 milestones (M1, M2, M3, M4, M5, M6, M6.5, M7). Calendar time depends on cadence. The app is daily-usable from M1 onward.

## Anthropic API Cost

Estimated $30-80 in API spend for the full v1 build using Claude Sonnet 4.6 as the executor with occasional Opus 4.7 calls for parser/architecture work. Zero ongoing infrastructure cost. Only ongoing cost is $99/year Apple Developer if you ship.
