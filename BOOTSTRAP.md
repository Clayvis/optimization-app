# BOOTSTRAP.md

Copy and paste the entire fenced block below as your first message to Claude Code.

---

```
Read these files in this order before responding:
1. CLAUDE.md
2. README.md
3. PROJECT_BRIEF.md
4. ARCHITECTURE.md
5. DATA_MODELS.md
6. MILESTONES.md
7. PERFORMANCE.md
8. TESTING.md
9. SECURITY.md

Confirm you have read all by listing:
- The 3 highest-priority user communication preferences from CLAUDE.md.
- The 13 SwiftData models defined in DATA_MODELS.md.
- The Definition of Done for M1 from MILESTONES.md.
- The watch performance targets from PERFORMANCE.md.

Before any tool calls, ask me for these inputs:
1. Apple Developer Team ID for the bundle identifier (e.g., "com.clayrawlins"). Replace <YOUR-TEAM> placeholders throughout the project.
2. Whether I have a paid Apple Developer Program account ($99/year) or free personal team.
3. Test devices available: iPhone model, watchOS version, Apple Watch Ultra hardware.

After I answer:
1. Create .work/state.json with active_milestone="M1", status="planning".
2. Plan M1 per CLAUDE.md "Execution Loop". Surface unknowns before coding.
3. Wait for my approval of the plan.
4. Execute M1 task by task. Run tests after each task. Commit after each passing test.
5. At M1 close: open PR, run all Quality Gates from CLAUDE.md, merge to main, tag m1-complete.
6. STOP. Do not start M2 without my signal.

Constraints:
- Communication preferences in CLAUDE.md are mandatory every response.
- ZERO third-party Swift packages. Apple frameworks only.
- One milestone in flight at a time.
- Each milestone closes with passing build, green tests, performance benchmarks met, PR to main.
- SwiftData models locked in DATA_MODELS.md. Use those exact specs.
- If a question requires my input, ask once with concrete options. Do not stack questions.

Begin.
```

---

## Required Permissions in ~/.claude/settings.json

Before launching, ensure your Claude Code permissions allow autonomous build operations:

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(gh:*)",
      "Bash(xcodebuild:*)",
      "Bash(swift:*)",
      "Bash(xcrun:*)",
      "Bash(npm:*)",
      "Bash(npx:*)",
      "Bash(node:*)",
      "Bash(mkdir:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(grep:*)",
      "Bash(find:*)",
      "Bash(cp:*)",
      "Bash(mv:*)",
      "Bash(rm:*)",
      "Edit(*)",
      "Write(*)",
      "Read(*)"
    ]
  }
}
```

Without these permissions, Claude Code halts at every git commit asking permission. With them set, it runs unattended through full milestones.

## What to Expect After Pasting

| Phase | Duration | What happens |
|-------|----------|--------------|
| File reading | 30-60 sec | Agent reads 9 docs, confirms understanding |
| Bootstrap inputs | 2-5 min | Agent asks 3 questions, you answer |
| M1 planning | 5-10 min | Agent proposes M1 plan, you approve |
| M1 execution | 8-12 hours | Xcode project, models, schedule engine, watch complication |
| M1 close | 5 min | PR opened, Quality Gates run, merge, tag |

After M1 closes, the agent stops. Next session, you say "begin M2" and the loop repeats.

## Resuming a Session

If a session ends mid-milestone, resume with:

```bash
cd ~/projects/optimization-app
claude

# First message:
> Read .work/state.json and resume the active milestone per CLAUDE.md.
```

The agent reads state.json, sees the active milestone and last task, continues from there.

## If Something Breaks

| Symptom | Fix |
|---------|-----|
| "Permission to use Bash has been denied" | Add the missing command to `~/.claude/settings.json` permissions block above |
| Xcode CLI tools missing | `xcode-select --install` |
| `gh` not found | `brew install gh` then `gh auth login` |
| `xcodebuild` fails on first build | Search the project for `<YOUR-TEAM>` and replace with your Team ID |
| Agent forgets context mid-session | Context window full. Tell agent: "read .work/state.json and resume", then continue |
| Agent goes off-rails | Ctrl+C, say "stop, re-read CLAUDE.md, return to last passing commit" |
| API rate limit hit | Switch to claude-haiku-4-5 for routine work, save Sonnet/Opus for parser/architecture |

## Cost Tracking

Estimated API spend per milestone:

| Milestone | Estimated tokens | Estimated cost (Sonnet 4.6) |
|-----------|------------------|-----------------------------|
| M1 | 200k-400k | $1-3 |
| M2 | 300k-500k | $2-4 |
| M3 | 600k-1M | $4-7 |
| M4 | 200k-400k | $1-3 |
| M5 | 800k-1.2M | $6-9 |
| M6 | 400k-700k | $3-5 |
| M6.5 | 400k-700k | $3-5 |
| M7 | 600k-900k | $4-7 |
| **Total** | **3.5M-5.8M** | **$24-43** |

Add 30% buffer for retries and Quality Gate failures. Actual range $30-60. Higher if Opus 4.7 used for non-routine work.

## Stopping Gracefully

Mid-milestone: tell the agent "stop, write current progress to .work/state.json, commit any in-progress work to a branch, exit." Then close the terminal.

End of milestone: agent should auto-stop per CLAUDE.md. If it tries to start the next milestone, say "stop, M1 is complete, do not start M2."
