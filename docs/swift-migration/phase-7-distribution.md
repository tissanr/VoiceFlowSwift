# Phase 7 — Distribution & Cleanup

> **Dauer:** 1–2 Wochen | **Vorgänger:** Phase 6 | **Nachfolger:** —

## Ziel

Signierte, notarisierte `.app` die per `brew install --cask voiceflow` installierbar ist —
und den Python-Stack vollständig ablöst.

## Warum jetzt

Erst wenn alle Phasen stabil und getestet sind. Distribution ist der letzte Schritt,
nicht ein Zwischenschritt.

---

## Komponenten

### 7.1 Code Signing & Notarisierung

Das ist der größte Unterschied zum bisherigen Python-Stack: die Swift-App kann **echte
Code-Signing + Notarisierung** erhalten, womit `xattr -dr com.apple.quarantine` entfällt.

**Voraussetzungen:**

- Apple Developer Account ($99/Jahr)
- Developer ID Application Certificate im Keychain

**Xcode Build Settings:**

```
CODE_SIGN_IDENTITY = "Developer ID Application: Stephan ..."
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM = XXXXXXXXXX
ENABLE_HARDENED_RUNTIME = YES
```

**Notarisierung via `notarytool`:**

```bash
# App archivieren
xcodebuild archive -scheme VoiceFlow -archivePath VoiceFlow.xcarchive

# Export als Developer ID .app
xcodebuild -exportArchive \
  -archivePath VoiceFlow.xcarchive \
  -exportPath ./dist \
  -exportOptionsPlist ExportOptions.plist

# Notarisieren
xcrun notarytool submit dist/VoiceFlow.app \
  --apple-id "..." --team-id "..." --password "@keychain:AC_PASSWORD" \
  --wait

# Staple (Notarisierungs-Ticket in .app einbetten)
xcrun stapler staple dist/VoiceFlow.app
```

**Entitlements** (`VoiceFlow.entitlements`):

```xml
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.automation.apple-events</key><true/>
<!-- Hardened Runtime: keine weiteren Entitlements nötig für AX/Input Monitoring -->
<!-- AX + Input Monitoring werden zur Laufzeit via TCC angefragt, nicht per Entitlement -->
```

**Risiken:**

- Hardened Runtime blockiert ggf. CGEventTap — testen ob Input Monitoring Permission-Dialog
  korrekt erscheint
- AX API unter Hardened Runtime: `AXUIElementCopyAttributeValue` benötigt
  `com.apple.security.temporary-exception.apple-events` wenn App in Sandbox — **nicht** in
  Sandbox einreichen (Developer ID, nicht App Store)

---

### 7.2 GitHub Actions Release-Pipeline (neu)

**Ersetzt:** `.github/workflows/release.yml` (aktuell Python-Build)

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    tags: ["v*"]
jobs:
  build:
    runs-on: macos-14 # Apple Silicon
    steps:
      - uses: actions/checkout@v4
      - name: Import Certificate
        # P12 aus GitHub Secrets importieren
        run: |
          echo "${{ secrets.CERTIFICATE_P12 }}" | base64 -d > cert.p12
          security import cert.p12 -P "${{ secrets.CERTIFICATE_PASSWORD }}" \
            -T /usr/bin/codesign
      - name: Build & Archive
        run: xcodebuild archive -scheme VoiceFlow -archivePath VoiceFlow.xcarchive
      - name: Export & Notarize
        run: |
          xcodebuild -exportArchive ...
          xcrun notarytool submit ...
          xcrun stapler staple ...
      - name: Package ZIP
        run: |
          cd dist && zip -r --symlinks "VoiceFlow-${VERSION}.zip" VoiceFlow.app
          SHA256=$(shasum -a 256 "VoiceFlow-${VERSION}.zip" | awk '{print $1}')
          echo "sha256=${SHA256}" >> $GITHUB_OUTPUT
      - uses: softprops/action-gh-release@v2
        with:
          files: "dist/VoiceFlow-*.zip"
```

**Secrets die in GitHub hinterlegt werden müssen:**

- `CERTIFICATE_P12` — Developer ID Certificate als Base64-P12
- `CERTIFICATE_PASSWORD` — P12-Passwort
- `NOTARIZATION_APPLE_ID`
- `NOTARIZATION_TEAM_ID`
- `NOTARIZATION_PASSWORD` — App-specific Password von appleid.apple.com

---

### 7.3 Homebrew Cask (vereinfacht)

Mit notarisierter App entfällt der `postflight xattr`-Block komplett.
Kein `postflight pip install` mehr — die `.app` ist self-contained.

```ruby
# homebrew-tap/Casks/voiceflow.rb
cask "voiceflow" do
  version "2.0.0"
  sha256 "..."  # aus Release-Notes

  url "https://github.com/tissanr/VoiceFlow/releases/download/v#{version}/VoiceFlow-#{version}.zip"
  name "VoiceFlow"
  desc "Local macOS push-to-talk voice-to-text app using on-device AI"
  homepage "https://github.com/tissanr/VoiceFlow"

  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

  app "VoiceFlow.app"

  # Kein postflight mehr — App ist signiert und notarisiert

  uninstall quit: "com.voiceflow.app"
  zap trash: "~/.voiceflow"

  caveats <<~EOS
    Beim ersten Start fragt macOS nach drei Berechtigungen — alle erlauben:
      • Mikrofon
      • Accessibility (Eingabehilfen)
      • Input Monitoring

    Hotkey: Fn + Shift gedrückt halten → sprechen → loslassen
  EOS
end
```

---

### 7.4 XCTest-Suite vervollständigen

Alle Unit-Tests aus den vorherigen Phasen finalisieren:

| Testklasse              | Abdeckung                                            |
| ----------------------- | ---------------------------------------------------- |
| `AppSettingsTests`      | Laden, Speichern, Defaults                           |
| `WordLoggerTests`       | Append, Read, JSONL-Kompatibilität mit Python-Logs   |
| `HotkeyManagerTests`    | Mock-Callbacks, Start/Stop                           |
| `AudioRecorderTests`    | Stille RMS, Format-Check                             |
| `TranscriberTests`      | Halluzinations-Filter, Retry-Logik (Mock-WhisperKit) |
| `VocabLearnerTests`     | Lernen, Anwenden, LRU-Eviction                       |
| `LLMPostProcessorTests` | Output-Validierung, Fallback auf Original            |
| `OllamaProcessorTests`  | Request-Format, Timeout, Mock-URLSession             |
| `TextNormalizerTests`   | Alle Ersetzungsregeln                                |
| `TextInjectorTests`     | TYPE-Events, AX-Insert (Mock-AX)                     |
| `CursorContextTests`    | Strategie-Auswahl, Electron-Fallback (Mock-AX)       |
| `TextDeliveryTests`     | Routing nach Bundle-ID                               |

**Integration-Tests** (laufen auf echtem Gerät, kein CI):

- End-to-End: Aufnahme → Transkription → Injektion in TextEdit
- Electron-Test: Injektion in VS Code

---

### 7.5 Python-Stack entfernen

Erst wenn Swift-App vollständig funktioniert und auf `main` gemergt ist:

```bash
# Aus dem Repository entfernen:
git rm -r core/ ui/ settings/ main.py build_app.py requirements.txt requirements-dev.txt
git rm -r venv/   # .gitignore, nicht getrackt — nur dokumentieren
git rm -r tests/  # Python-Tests durch XCTest ersetzt

# Homebrew-Tap aktualisieren:
# homebrew-tap/Formula/voiceflow.rb löschen (kein Python-Build mehr)
# homebrew-tap/Casks/voiceflow.rb auf neue SHA256 aktualisieren
```

---

## Done-Kriterium

- [ ] `spctl --assess --verbose ~/Applications/VoiceFlow.app` → `accepted`
- [ ] App startet auf frischem Mac ohne `xattr`-Kommando
- [ ] `brew install --cask tissanr/voiceflow/voiceflow` installiert die App in einem Schritt
- [ ] Alle XCTest-Tests grün auf CI (GitHub Actions)
- [ ] `~/.voiceflow/settings.json` vom Python-Stack wird korrekt gelesen (Rückwärtskompatibilität)
- [ ] Python-Verzeichnisse aus Repository entfernt, CLAUDE.md aktualisiert

## Offene Fragen

- Apple Developer Account bereits vorhanden oder muss er neu angelegt werden?
- Soll die App im Mac App Store veröffentlicht werden (Sandbox-Einschränkungen!)
  oder nur als Developer ID (empfohlen wegen AX API)?
- Versionsnummer: `2.0.0` für Swift-Rewrite oder weiter bei `1.x`?
