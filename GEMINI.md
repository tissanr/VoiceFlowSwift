# Gemini — Project Instructions

This file establishes the context for Gemini. To avoid duplication, it primarily links to existing documentation.

## Core Documentation
- **[CLAUDE.md](CLAUDE.md)**: Contains detailed instructions, conventions, and build/test commands. Follow these strictly.
- **[ROADMAP.md](ROADMAP.md)**: Current development status, architecture, and open points.
- **[Swift Migration Docs](docs/swift-migration/README.md)**: Detailed phase-by-phase documentation for the Swift migration.

## Build & Test (from CLAUDE.md)
```bash
# Build
xcodebuild build -project VoiceFlow/VoiceFlow.xcodeproj -scheme VoiceFlow -configuration Debug

# Test
xcodebuild test -project VoiceFlow/VoiceFlow.xcodeproj -scheme VoiceFlow -destination 'platform=macOS'
```

## Next Steps
See [ROADMAP.md](ROADMAP.md) for the current status. The project is currently in the transition from Phase 3 to Phase 4 of the Swift migration.
