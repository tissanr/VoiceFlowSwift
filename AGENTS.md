# Codex Agent Notes

`CLAUDE.md` is the first-order AI context for this repository. Read it first, then use this file only for Codex-specific workflow details that should not be duplicated there.

## Codex Workflow

- Work from `origin/swift-migration-pr` for the current Swift migration work. `main` may lag behind active Phase 2/Phase 3 changes.
- If the checkout is detached, create a `codex/...` branch before editing.
- Keep `CLAUDE.md` authoritative for product context, phase rules, project conventions, and roadmap update expectations.
- Do not copy large sections from `CLAUDE.md` into this file. Add only Codex execution notes, branch hazards, and verification shortcuts here.

## Local Commands

Run build commands from the repository root with the project path explicit:

```bash
xcodebuild build -project VoiceFlow/VoiceFlow.xcodeproj -scheme VoiceFlow -configuration Debug
```

There is currently no XCTest target in the project. If tests are added, prefer:

```bash
xcodebuild test -project VoiceFlow/VoiceFlow.xcodeproj -scheme VoiceFlow -destination 'platform=macOS'
```

## Current Implementation Notes

- Phase 2 lives on `swift-migration-pr`: `AudioRecorder`, `HotkeyManager`, `OverlayLevelMapper`, and the manual `main.swift` app entry point are implemented there.
- Phase 3 is implemented in this branch: `ModelManager`, `ModelDownloader`, `Transcriber`, and `VocabLearner`.
- `VoiceFlow/VoiceFlow.xcodeproj/project.pbxproj` currently uses file-system-synchronized groups, so new Swift files under `VoiceFlow/VoiceFlow/` may not need manual project-file edits in recent Xcode versions.
- The project currently pins WhisperKit to the `main` branch. Treat dependency behavior as moving until it is pinned to a release or commit.

## Review Focus For Codex

- Pay close attention to app lifecycle, permissions, and global event tap cleanup. These are hard to validate with unit tests alone.
- Keep user-facing logs and comments in German unless the surrounding file is clearly English.
- Avoid adding new persistent storage locations; compatibility paths under `~/.voiceflow/` are intentional.
- Before wiring UI around Phase 3, run a real microphone-to-Whisper pass. The current verification is compile-level only.
