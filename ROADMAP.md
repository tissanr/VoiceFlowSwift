# VoiceFlow – Roadmap & Entwicklungsdokumentation

> **Letzte Aktualisierung:** 2026-05-15 (Swift Phase 2/3 implementiert)
> **Maintainer:** Eduard Munt
> **Zweck:** Nachvollziehbare Entwicklungsgeschichte, aktueller Stand, offene Punkte

---

## Projektübersicht

VoiceFlow ist eine lokale macOS Menubar-App für Push-to-Talk Sprache-zu-Text.
Keine Cloud, keine Subscription — alles läuft lokal auf Apple Silicon.

**Hotkey:** `Fn + Shift` (halten zum Aufnehmen, loslassen zum Transkribieren)
**Starten:** `python main.py`

### Swift-Migration aktueller Stand

Die aktive Swift-Migration liegt im Xcode-Projekt `VoiceFlow/VoiceFlow.xcodeproj`.
Der aktuelle Implementierungszweig ist `swift-migration-pr`; `main` kann zeitweise hinterherhinken.

- Phase 1: Foundation, Settings, Logging und App-Skeleton implementiert.
- Phase 2: `AudioRecorder`, `HotkeyManager` und `OverlayLevelMapper` implementiert.
- Phase 3: WhisperKit-Transcriber, Modell-Cache/-Download und `VocabLearner` implementiert.
- Noch offen: echter Mikrofon-zu-Whisper-End-to-End-Test, XCTest-Target, Phase 4–7.

### Tech-Stack

| Komponente          | Technologie                           |
| ------------------- | ------------------------------------- |
| Spracherkennung     | mlx-whisper (Apple Silicon optimiert) |
| LLM Post-Processing | mlx-lm (Phi-4-mini, Qwen 2.5)         |
| UI                  | rumps (macOS Menubar)                 |
| Text-Injektion      | CGEventPost (Quartz)                  |
| Accessibility       | ApplicationServices (AX API)          |
| Hotkey-Erkennung    | CGEventSourceKeyState (Quartz)        |

---

## Architektur

```
main.py
  └─ ui/menubar_app.py          ← Zentrale Steuerung, Pipeline
       ├─ core/hotkey_manager.py    ← Fn+Shift Polling (40ms)
       ├─ core/audio_recorder.py   ← Mikrofon-Aufnahme
       ├─ core/transcriber.py      ← mlx-whisper Wrapper
       ├─ core/cursor_context.py   ← Cursor-Position via AX API
       ├─ core/llm_post_processor.py ← LLM Korrektur (mlx-lm)
       ├─ core/vocab_learner.py    ← Automatisches Vokabular-Lernen
       ├─ core/text_injector.py    ← CGEventPost Text-Injektion
       ├─ core/post_processor.py   ← Einfache Textnachbearbeitung
       ├─ core/word_logger.py      ← Statistik
       └─ settings/app_settings.py ← Persistente Einstellungen
```

### Transkriptions-Pipeline

```
Hotkey gedrückt
  → get_context_before_cursor()   [AX API, vor Overlay]
  → AudioRecorder.start()
  → Overlay anzeigen

Hotkey losgelassen
  → AudioRecorder.stop()
  → WhisperTranscriber.transcribe(audio, initial_prompt=vocabulary)
  → apply_learned_corrections(text, vocab_cache)   [immer]
  → LLMPostProcessor.process(text, capitalize, vocabulary)  [wenn aktiviert]
  → VocabLearner.learn(original, corrected)  [im Hintergrund, wenn LLM Änderungen]
  → should_capitalize(cursor_context) → Groß/Klein anpassen
  → deliver_text(text, cursor_context, frontmost_bundle)
```

---

## Persistente Dateien

| Datei                           | Inhalt                                             |
| ------------------------------- | -------------------------------------------------- |
| `~/.voiceflow/settings.json`    | App-Einstellungen (Modell, Sprache, LLM an/aus, …) |
| `~/.voiceflow/vocab_cache.json` | Gelernte Korrekturen `{"opener eye": "OpenAI", …}` |
| `~/.voiceflow/voiceflow.log`    | Laufzeit-Log (stdout + stderr)                     |
| `~/.voiceflow/word_log.json`    | Wort-Statistiken (heute / 7 Tage / gesamt)         |

---

## Abgeschlossen

### 2026-05-12 — Distribution: Homebrew-Tap vorbereitet

**Ziel:** Neue Nutzer sollen VoiceFlow via `brew install --cask voiceflow` installieren können.

**Lösung:**

- `build_app.py`: neue Flags `--python`, `--script`, `--dest`, `--bundle`
  - `--bundle`: Quellcode wird in `Contents/Resources/src/` eingebettet; C-Launcher löst Pfade zur Laufzeit via `_NSGetExecutablePath` auf (kein Hardcoding mehr)
  - `--python`/`--script`/`--dest`: erlauben dem Homebrew-Formula eigene Installationspfade zu setzen
- `.github/workflows/release.yml`: Release-Pipeline – baut bei `git tag v*` automatisch das Bundle-App, verpackt es als ZIP und erstellt ein GitHub Release mit SHA256
- `homebrew-tap/Casks/voiceflow.rb`: Cask-Formula – lädt fertiges `.app` herunter, richtet Python-Venv in `Contents/Resources/venv/` ein, entfernt Quarantäne
- `homebrew-tap/Formula/voiceflow.rb`: Source-Formula – baut aus Quellcode, installiert nach `libexec`, verlinkt .app nach `~/Applications`
- `homebrew-tap/README.md`: Installations-Dokumentation

**Nächste Schritte:**

1. Neues GitHub-Repo `tissanr/homebrew-voiceflow` anlegen
2. Inhalt von `homebrew-tap/` dorthin pushen
3. Ersten Release-Tag setzen: `git tag v1.0.0 && git push origin v1.0.0`
4. SHA256 aus dem Release in `Casks/voiceflow.rb` eintragen

**Geänderte/neue Dateien:**

- `build_app.py`
- `.github/workflows/release.yml` (neu)
- `homebrew-tap/Casks/voiceflow.rb` (neu)
- `homebrew-tap/Formula/voiceflow.rb` (neu)
- `homebrew-tap/README.md` (neu)

---

### 2026-05-12 — Feature: Terminal-Unterstützung (Text-Injektion in Terminal-Apps)

**Problem:** VoiceFlow konnte keinen Text in Terminal-Fenster (Terminal.app, iTerm2 etc.) injizieren. Da Terminal-Apps keine AX-Cursor-Position liefern, fiel die Delivery-Pipeline auf Clipboard-only zurück — nutzlos für Shell-Arbeit.

**Lösung:**

- `core/text_delivery.py`: Neues `TERMINAL_BUNDLES`-Set mit Bundle-IDs bekannter Terminal-Apps (`com.apple.Terminal`, `com.googlecode.iterm2`, `com.github.wez.wezterm`, `net.kovidgoyal.kitty`, `co.zeit.hyper`, `io.alacritty`).
- Neuer Delivery-Pfad: wenn `frontmost_bundle in TERMINAL_BUNDLES` → Text via TYPE (Keyboard-Events aus dem C-Launcher) injizieren, ohne Cursor-Kontext-Anforderung.
- Trailing Newlines werden vor der Injektion entfernt (`_strip_trailing_newlines`), damit kein Return-Keyevent den Shell-Befehl ungewollt ausführt.
- Kapitalisierungs-Logik entfällt für Terminals (kein Cursor-Kontext → Text kommt so wie Whisper ihn ausgibt).

**Geänderte Dateien:**

- `core/text_delivery.py`

**Tests:** 248 passed, 5 skipped.

### 2026-04-30 — Textausgabe-Modi semantisch getrennt

**Problem:** Der Modus „Text einfügen“ nutzte bei vorhandenem Cursor-Kontext
trotzdem zuerst AX-Direkteinfügung oder Tipp-Events. Dadurch waren die beiden
Optionen aus Nutzersicht nicht klar getrennt und Absatz-/Cursor-Verhalten in
Codex/Claude schwer nachvollziehbar.

**Lösung:**

- „Text tippen“ wurde zu „Text tippen (ohne Zwischenablage)“
- „Text einfügen“ bleibt als cursorbasierter Einfüge-Modus sichtbar, ohne
  Paste/Clipboard-Versprechen bei vorhandenem Cursor.
- Tipp-Modus nutzt keinen Clipboard-Fallback mehr. Wenn AX/TYPE nicht greifen,
  scheitert die Ausgabe sichtbar im Log, statt Text heimlich zu kopieren.
- Einfüge-Modus mit Cursor-Kontext restauriert zuerst den Cursor und nutzt dann
  ausschließlich AX/TYPE ohne Clipboard.
- Clipboard wird nur genutzt, wenn kein Cursor-Kontext vorhanden ist. In diesem
  Fall ist es ein bewusster Fallback und der Text bleibt absichtlich in der
  Zwischenablage.

**Geänderte Dateien:**

- `core/text_delivery.py`
- `ui/menubar_app.py`
- `tests/test_menubar_delivery.py`
- `ROADMAP.md`

### 2026-04-30 — Fix: AX-Middle-Insert nur bei echtem Textkontext

**Problem:** Der Hybrid-Fix für mittige Absatz-Injektion wurde auch bei reinem Newline-/Placeholder-Kontext (`cursor_context == "\n"`) aktiv. Dadurch wurde der Placeholder/Folgetext `Nach Folgeänderungen fragen` als echter Folgetext betrachtet und ein `AXValue`-Insert mit Absatztrenner ausgeführt. Das konnte beim ersten Output in einem leeren Editor den Cursor an den Satzanfang bzw. in einen inkonsistenten Editor-State bringen.

**Lösung:**

- `core/text_delivery.py`: `_direct_middle_insert_text()` bricht jetzt ab, wenn `cursor_context.strip()` leer ist. Der AX-Middle-Insert mit Trenner läuft nur noch bei echtem Text vor dem Cursor, z.B. `Das ist Test 1.\n\n`.
- Reiner Newline-/Placeholder-Kontext nutzt wieder den normalen Cursor-Restore+TYPE-Pfad ohne AX-Middle-Insert.
- Regressionstest ergänzt: `cursor_context == "\n"` darf auch bei gemeldetem Folgetext keinen `direct:'Hallo\n'`-Insert auslösen.

**Tests:** `venv/bin/python -m pytest` → 233 passed, 4 skipped; `venv/bin/python -m ruff check core/text_delivery.py core/text_injector.py tests/test_menubar_delivery.py` → passed.

**Geänderte Dateien:**

- `core/text_delivery.py`
- `tests/test_menubar_delivery.py`
- `ROADMAP.md`

### 2026-04-30 — Fix: Mittiger Folgeabsatz ohne Return-Keyevent

**Problem:** Beim Einfügen zwischen zwei Absätzen klebte der folgende Absatz direkt hinter dem neuen Text. Der naheliegende Fix, nach dem diktierten Text einen Newline-Run per `TYPE` zu senden, war falsch, weil `\n` im TYPE-Pfad als Return-Keyevent gesendet wird und Chat-Editoren dadurch Nachrichten abschicken können.

**Lösung:**

- `core/text_injector.py`: `has_text_after_cursor_context()` prüft wieder, ob hinter `cursor_context` bereits Text im aktuellen AXValue steht.
- `core/text_delivery.py`: Im Cursor-Restore+TYPE-Pfad gilt jetzt:
  - Kein Folgetext hinter dem Cursor → normales clipboard-freies `TYPE` nur mit diktiertem Text.
  - Folgetext hinter einem Newline-Kontext → gezielter `AXValue`-Insert mit `text + newline_run`, ohne Clipboard und ohne Return-Keyevent.
  - Wenn dieser AX-Insert scheitert → Fallback auf normales `TYPE` ohne Newline-Suffix.
- Regressionstest stellt sicher, dass im mittigen Absatzfall `direct:'Hallo\n\n'` verwendet wird und kein `inject:'Hallo\n\n'`.

**Tests:** `venv/bin/python -m pytest` → 232 passed, 4 skipped; `venv/bin/python -m ruff check core/text_delivery.py core/text_injector.py tests/test_menubar_delivery.py` → passed.

**Geänderte Dateien:**

- `core/text_delivery.py`
- `core/text_injector.py`
- `tests/test_menubar_delivery.py`
- `ROADMAP.md`

### 2026-04-30 — Revert: Kein Newline-Suffix nach TYPE

**Problem:** Der Fix "Mittige Absatz-Injektion erhält Folgeabsatz" hängte im clipboard-freien `TYPE`-Pfad bei vorhandenem Folgetext einen Newline-Run an den diktierten Text an. In Chat-Editoren ist das gefährlich: ein abschließender Return kann den Chat direkt abschicken.

**Lösung:**

- `core/text_delivery.py`: Newline-Suffix-Logik im Cursor-Restore+TYPE-Pfad entfernt. `TYPE` sendet wieder ausschließlich den diktierten Text.
- `core/text_injector.py`: `has_text_after_cursor_context()` entfernt, da sie nur für die gefährliche Suffix-Logik genutzt wurde.
- Tests zurückgedreht, damit der Absatzgrenzen-Pfad keine zusätzlichen Newline-/Return-Events mehr erwartet.

**Tests:** `venv/bin/python -m pytest` → 231 passed, 4 skipped; `venv/bin/python -m ruff check core/text_delivery.py core/text_injector.py tests/test_menubar_delivery.py` → passed.

**Geänderte Dateien:**

- `core/text_delivery.py`
- `core/text_injector.py`
- `tests/test_menubar_delivery.py`
- `ROADMAP.md`

### 2026-04-30 — Fix: Mittige Absatz-Injektion erhält Folgeabsatz

**Problem:** Beim Einfügen in eine leere Zeile zwischen zwei Absätzen wurde der neue Text korrekt an der Cursorposition getippt, aber der folgende Absatz rückte direkt hinter den neuen Text (`Test 3.Test 2`). Ursache: Der clipboard-freie `TYPE`-Pfad fügte nur den diktierten Text ein. Wenn hinter der Cursorposition bereits Text existiert, muss zusätzlich der bestehende Absatztrenner nach dem neuen Text erhalten bleiben.

**Lösung:**

- `core/text_injector.py`: neue Funktion `has_text_after_cursor_context()` prüft über den aktuellen `AXValue`, ob hinter `cursor_context` noch Text steht.
- `core/text_delivery.py`: Im Cursor-Restore+TYPE-Pfad wird bei einem trailing Newline-Run im Kontext und vorhandenem Folgetext derselbe Newline-Run an den diktierten Text angehängt. Beispiel: Kontext endet mit `\n\n`, Folgetext existiert → VoiceFlow tippt `Neuer Text.\n\n`.
- Regressionstest für mittiges Einfügen zwischen Absätzen ergänzt.

**Tests:** `venv/bin/python -m pytest` → 232 passed, 4 skipped; `venv/bin/python -m ruff check core/text_delivery.py core/text_injector.py tests/test_menubar_delivery.py` → passed.

**Geänderte Dateien:**

- `core/text_delivery.py`
- `core/text_injector.py`
- `tests/test_menubar_delivery.py`
- `ROADMAP.md`

### 2026-04-30 — Fix: Absatzgrenzen clipboard-frei via Cursor-Restore + TYPE

**Problem:** Der vorherige Fix nutzte bei Absatzgrenzen temporären nativen Paste. Das erhielt zwar die Absatzstruktur besser als `AXValue`, schrieb den diktierten Text aber kurzzeitig in die Zwischenablage. Clipboard-Manager können diesen temporären Inhalt sehen; das widerspricht dem Ziel, Cursor-Injektion clipboard-frei zu halten.

**Lösung:**

- `core/text_delivery.py`: Codex/Rich-Text-Sonderpfad und Absatzgrenzen (`cursor_context.endswith("\n")`) nutzen jetzt `set_cursor_position_from_context()` + `inject_text()` (`TYPE`) statt `paste_text()`.
- Der Delivery-Pfad importiert `paste_text` nicht mehr; für diese Fälle gibt es keinen Clipboard-Fallback. Wenn `TYPE` fehlschlägt, wird nur noch Direct-Insert versucht oder der Vorgang scheitert ohne Clipboard-Schreibzugriff.
- Tests auf clipboard-freien Ablauf angepasst: kein `paste_text`, kein `copy_to_clipboard` im Codex-/Absatzgrenzen-Pfad.

**Tests:** `venv/bin/python -m pytest` → 231 passed, 4 skipped; `venv/bin/python -m ruff check core/text_delivery.py tests/test_menubar_delivery.py` → passed.

**Geänderte Dateien:**

- `core/text_delivery.py`
- `tests/test_menubar_delivery.py`
- `ROADMAP.md`

### 2026-04-30 — Fix: Absatzgrenzen nutzen nativen Paste statt AXValue

**Problem:** Nach dem Fix gegen den falschen `TYPE`-Fallback wurde Text zwar hinter den vorhandenen Text eingefügt, aber nicht als echter neuer Absatz gerendert. Die Logs zeigten, dass `cursor_context` korrekt mit `\n\n` endete und der Insert rechnerisch an der richtigen Position passierte. Ursache: Direct-Insert über `AXValue` schreibt Plaintext in den Editor-State; Claude Code/Codex rendern dabei die Absatzstruktur nicht zuverlässig wie bei nativer Eingabe/Paste.

**Lösung:**

- `core/text_delivery.py`: Wenn ein bekannter `cursor_context` mit einem Zeilenumbruch endet, wird zuerst der temporäre native Paste-Pfad verwendet (`set_cursor_position_from_context()` + `paste_text()`), statt direkt `AXValue` zu setzen.
- Direct-Insert bleibt Fallback, falls temporärer Paste technisch fehlschlägt.
- Regressionstests stellen sicher, dass Absatzkontexte (`cursor_context.endswith("\n")`) vor Direct-Insert über temporären Paste laufen.

**Tests:** `venv/bin/python -m pytest` → 231 passed, 4 skipped; `venv/bin/python -m ruff check core/text_delivery.py tests/test_menubar_delivery.py` → passed.

**Geänderte Dateien:**

- `core/text_delivery.py`
- `tests/test_menubar_delivery.py`
- `ROADMAP.md`

### 2026-04-30 — Fix: Kein TYPE-Fallback nach erfolgreichem AXValue-Insert

**Problem:** Im Claude-Code-Editor wurde Text nach einem Absatz an der falschen Stelle eingefügt. Aus den Logs war sichtbar: `insert_text_direct()` setzte den neuen `AXValue` bereits korrekt (`current + inserted` am Ende des Kontextes), aber das anschließende Setzen der Cursor-Range schlug fehl. Der Code rollte daraufhin den erfolgreichen Text-Set zurück und fiel auf `TYPE` zurück. Dieses simulierte Tippen landete dann an der alten/falschen Editor-Selektion, wodurch der Text vor dem vorhandenen Inhalt erschien.

**Lösung:**

- `core/text_injector.py`: Wenn `AXUIElementSetAttributeValue(kAXValueAttribute, updated)` erfolgreich war, wird der Insert als erfolgreich behandelt, auch wenn das nachgelagerte Setzen von `kAXSelectedTextRangeAttribute` nicht verifiziert werden kann.
- Kein Rollback und kein `TYPE`-Fallback mehr nach erfolgreichem `AXValue`-Set. Dadurch bleibt der bereits korrekt eingefügte Text erhalten.
- Regressionstest mit AppKit-/ApplicationServices-Stubs ergänzt: erfolgreicher `AXValue`-Set, fehlgeschlagener Cursor-Set, kein Zurücksetzen auf den alten Inhalt.

**Tests:** `venv/bin/python -m pytest` → 229 passed, 4 skipped; `venv/bin/python -m ruff check core/text_injector.py tests/test_text_injector.py` → passed.

**Geänderte Dateien:**

- `core/text_injector.py`
- `tests/test_text_injector.py`
- `ROADMAP.md`

### 2026-04-30 — Fix: Codex restauriert AX-Cursor vor Paste

**Problem:** In der Codex-Schreibzeile wurde diktierter Text bei mehreren Absätzen ans Textende angehängt. Claude Code war nicht betroffen. Reiner `AXValue`-Direktinsert ist für Codex ungeeignet, weil er den internen Rich-Text-/DOM-State durcheinanderbringen kann. Reiner nativer Paste reicht aber ebenfalls nicht, wenn Codex beim Fokuswechsel die Editor-Selektion ans Ende verliert.

**Lösung:**

- `core/text_injector.py`: neue Funktion `set_cursor_position_from_context()` setzt ausschließlich die AX-Selection (`kAXSelectedTextRangeAttribute`) auf `len(cursor_context)`, ohne `AXValue` zu verändern.
- `core/text_delivery.py`: Codex-Sonderpfad aktiviert Codex, restauriert die Cursor-Range aus dem vor der Aufnahme gespeicherten Kontext und führt erst danach temporären Clipboard-Paste (`paste_text()` + `Cmd+V`) aus.
- `core/cursor_context.py`: bestehende Newline-Run-Korrektur bleibt relevant, damit `cursor_context` bei `\n\n` wirklich bis hinter den Absatzumbruch reicht.
- Regressionstests für die Codex-Paste-Weiche und Prefix-basierte Cursor-Position ergänzt.

**Tests:** `venv/bin/python -m pytest` → 228 passed, 4 skipped; `venv/bin/python -m ruff check core/cursor_context.py core/text_delivery.py core/text_injector.py tests/test_cursor_context.py tests/test_text_injector.py tests/test_menubar_delivery.py` → passed.

**Geänderte Dateien:**

- `core/text_delivery.py`
- `core/text_injector.py`
- `tests/test_menubar_delivery.py`
- `tests/test_text_injector.py`
- `ROADMAP.md`

### 2026-04-29 — Fix: Text vor dem Link eingefügt (Claude Code Editor / Electron AX-Cursor-Bug)

**Problem:** Wenn der Nutzer einen Markdown-Link in einer Zeile im Claude Code Editor hatte und dann den Cursor zwei Absätze darunter setzte, wurde der diktierte Text VOR dem Link eingefügt statt an der tatsächlichen Cursor-Position.

**Ursachen (analysiert):**

1. **`current.startswith(cursor_context)` schlug fehl** → der Safety-Check in `_compose_direct_insert()` (der AX-Fehler bei `start=0` abfangen soll) griff nicht → Text wurde an Position 0 (vor dem Link) eingefügt.  
   Ursache des Mismatches: Electron/CodeMirror kann `AXValue` zwischen Cursor-Capture (Hotkey-Druck) und Injection (nach Transkription) leicht unterschiedlich liefern — z.B. normalisierte Whitespace, Link anders kodiert, oder AX-Fokus auf anderem Element.

2. **Placeholder-Erkennung (Check 2) zu aggressiv**: `current == cursor_context AND start == 0` setzte `looks_like_placeholder = True` → ganzer Textinhalt wurde gelöscht, nur neuer Text blieb. Betraf den Fall Cursor-am-Textende + AX meldet `start=0` fälschlicherweise.

**Fixes:**

- `core/text_injector.py` — `insert_text_direct()`: Diagnostik-Logging (`start`, `length`, `cur_len`, `ctx_len`, `startswith`, `ctx_tail`, `cur_head`) vor dem Einfügen. Neuer Sicherheits-Abbruch: wenn `cursor_context` > 10 Zeichen und `current.startswith(cursor_context)` False → sofortiges `return False` → TYPE-Fallback statt Einfügen an falscher Position.
- `core/text_injector.py` — `_compose_direct_insert()`: Check 2 (`current == cursor_context AND start == 0`) setzt nicht mehr `looks_like_placeholder = True` (würde Inhalt löschen), sondern korrigiert `start = len(current)` → Text wird am Ende angehängt.
- `tests/test_text_injector.py`: Bestehenden Check-2-Test aktualisiert (erwartet jetzt korrektes Anhängen statt Löschen). Drei neue Tests für das Link-Cursor-Szenario.

**Tests:** `venv/bin/python -m pytest` → 226 passed, 4 skipped.

**Geänderte Dateien:**

- `core/text_injector.py`
- `tests/test_text_injector.py`
- `ROADMAP.md`

---

### 2026-04-28 — Fix: Codex nutzt nativen Paste statt AXValue-Direktinsert

**Problem:** In der Codex-Schreibzeile konnte neuer diktierter Text, der visuell in einem Absatz nach bestehendem Text eingefügt werden sollte, an die vorherige Zeile bzw. direkt hinter den letzten Satz rutschen. Der erste Korrekturversuch über `insert_text_direct()` nutzte zwar die korrigierte AX-Cursorposition, setzte aber den kompletten `AXValue` neu. Bei Codex/Electron-Rich-Text-Editoren kann das den internen Editor-State bzw. die ursprüngliche Formatierung durcheinanderbringen.

**Lösung:**

- `core/cursor_context.py`: neue Hilfsfunktion `_include_visual_newline_run()` übernimmt bei der AX-Kontext-Extraktion die komplette zusammenhängende Newline-Sequenz statt nur ein einzelnes `\n`.
- Die direkte und die Tree/Closure-basierte Kontext-Extraktion verwenden dieselbe Newline-Run-Korrektur.
- `core/text_delivery.py`: Codex wird vor dem generischen AX-Direktinsert erkannt und nutzt stattdessen temporären Clipboard-Paste (`paste_text()` + `Cmd+V`) in die echte native Browser/Electron-Selektion. Dadurch wird der Rich-Text-/DOM-State nicht per `AXValue` überschrieben.
- Regressionstests für den Codex/Electron-Absatzfall und die Codex-Paste-Weiche ergänzt.

**Tests:** `venv/bin/python -m pytest` → 211 passed; `venv/bin/python -m ruff check core/cursor_context.py core/text_delivery.py tests/test_cursor_context.py tests/test_text_injector.py tests/test_menubar_delivery.py` → passed.

**Geänderte Dateien:**

- `core/cursor_context.py`
- `core/text_delivery.py`
- `tests/test_cursor_context.py`
- `tests/test_text_injector.py`
- `tests/test_menubar_delivery.py`
- `ROADMAP.md`

### 2026-04-27 — Performance: mlx-lm System-Prompt KV-Cache Pre-Filling

**Problem:** Bei jedem Diktat verarbeitete `mlx_lm.generate()` den vollständigen Prompt (System + User) von Grund auf neu. Der System-Prompt (~100–150 Tokens) ist für eine gegebene Konfiguration statisch und machte ~70–80 % des Prefill-Aufwands aus.

**Lösung:**

- `_prefill_system_cache(model, tokenizer, system_prompt)` — neue Hilfsfunktion. Tokenisiert den System-Prompt allein, prüft ob das Prefix im Full-Prompt stabil bleibt, befüllt einen `mlx_lm`-KV-Cache via `make_prompt_cache` + Forward-Pass, und speichert ihn in `_prompt_caches[system_prompt]`.
- `warmup()` — ruft nach dem Standard-Warmup-Inference `_prefill_system_cache` für die Standard-Konfiguration (minimal/standard) auf. Log: `[LLMPostProcessor] Prompt-Cache bereit (N Tokens).`
- `_run()` — Cache-aware: wenn `system_prompt in _prompt_caches`, werden nur die User-Tokens (nicht der volle Prompt) an `stream_generate` übergeben. Nach der Generation wird der Cache via `trim_prompt_cache` auf den System-Prompt-Stand zurückgeschnitten. Lazy-Fallback: bei unbekanntem System-Prompt wird nach der Standard-Inferenz ebenfalls ein Cache-Eintrag angelegt.
- `update_model()` und Model-Reload in `_run()` — leeren `_prompt_caches` und `_sys_token_counts` bei Modellwechsel.

**Erwartete Zeitersparnis:** ~40–60 % der mlx-lm LLM-Latenz pro Diktat (entfällt Prefill für ~100–150 statische System-Prompt-Tokens).

**Geänderte Dateien:**

- `core/llm_post_processor.py`

---

### 2026-04-27 — Fix: LLM-Warmup blockiert Startup bis Ollama warm ist (BUG-002)

**Problem:** `_warmup_ollama_bg()` wurde nach `show_ready()` in einem separaten Thread gestartet. Das Overlay zeigte "Modell bereit" während Ollama noch kalt war — die erste Spracheingabe traf auf einen kalten LLM-Call mit mehreren Sekunden Verzögerung.

**Lösung:**

`_warmup_ollama_bg()` wird jetzt synchron im Startup-Background-Thread aufgerufen, bevor `show_ready()` erscheint:

- `ui/overlay.py`: neue Methode `update_spinner_text(text)` + `_do_update_spinner_text` — aktualisiert den laufenden Spinner-Text thread-safe via `_on_main`
- `ui/menubar_app.py`: `_warmup_current()` zeigt "LLM lädt …" im Spinner während Ollama warmup läuft; `show_ready()` wird erst danach aufgerufen; separater `threading.Thread`-Start für Ollama entfernt

**Ergebnis:**

- "Modell bereit" erscheint erst wenn sowohl Whisper als auch Ollama warm sind
- Erste Spracheingabe nach Startup trifft auf warmes Modell ohne Verzögerung
- Wenn kein Ollama-Modell konfiguriert ist, wird der Schritt übersprungen
- Wenn Ollama nicht läuft, schlägt der Warmup nach 1 Sekunde (Connect-Timeout) still fehl — kein Hänger

**Geänderte Dateien:**

- `ui/overlay.py`
- `ui/menubar_app.py`

---

### 2026-04-26 — Feature: Analytics-Dashboard + Tab-Navigation im Verlauf-Fenster

**Was geändert:**

Das Verlauf-Fenster hat jetzt zwei Tabs direkt in der Titelleiste (Pill-Style):

- **Verlauf** — bestehende Transkriptions-Liste (unverändert)
- **Analyse** — neues Analytics-Dashboard mit 3 Zeilen Cards

**Dashboard-Inhalt (Analyse-Tab):**

- **Zeile 1:** WPM-Card (Gauge-Arc + Heute/7 Tage/Tagesrekord-Vergleich) + Gesamte-Wörter-Card (große Zahl, Kontext-String, 30T-Badge +X%, Sub-Stats Heute/7 Tage/30 Tage)
- **Zeile 2:** 30-Tage-Streak-Card mit GitHub-style Kalender-Heatmap (7 Wochentag-Zeilen × N Wochen-Spalten, 4 Intensitätsstufen Sky Blue, Hover-Highlight)
- **Zeile 3:** 4 Mini-Cards — Ø Sitzungsdauer, Sitzungen/30 Tage, Genauigkeit (WER aus LLM-Korrekturen), Längster Text

**Neues Feld in word_log.jsonl:** `"accuracy"` (0.0–1.0, SequenceMatcher-Ratio zwischen Whisper-Output und LLM-Korrektur) — wird beim nächsten Diktat mit aktivem LLM gefüllt.

**Geänderte Dateien:**

- `core/word_logger.py` — neue statische Methoden (`compute_wpm_windows`, `compute_period_change`, `compute_words_last_30_days`, `compute_words_per_day`, `compute_longest_streak`, `compute_sessions_last_30_days`, `compute_avg_duration_s`, `compute_max_session_words`, `compute_accuracy`), `log()` akzeptiert jetzt `correction_ratio`
- `ui/history_window.py` — Tab-Buttons, `_history_container`, `_analytics_scroll`, `_GaugeView`, `_HeatmapView`, alle Card-Builder-Funktionen, `_render_analytics()`
- `ui/menubar_app.py` — `correction_ratio` (SequenceMatcher) wird an `word_logger.log()` übergeben

---

### 2026-04-26 — Fix: Best-Effort-Delivery für Browser ohne AX-Cursor

**Problem:** Die frühere Aussage "Textfeld-Fokus in Chrome ist von außen nicht erkennbar" war zu absolut. Korrekt ist: Chrome/Browser/Electron liefern über AX häufig `None` bzw. `kAXErrorNoValue`, sodass AX allein nicht zuverlässig als Injection-Gate reicht. Der reine Bundle-ID-Fallback injizierte aber per TYPE auch dann, wenn kein Textfeld aktiv war, und konnte dabei still ins Leere laufen.

**Lösung:**

Die Entscheidung liegt jetzt zentral in `core/text_delivery.py`:

- `cursor_context is not None` → direkte `inject_text()`-Pipeline; Clipboard nur bei technischem Injection-Fehler
- Browser/Electron + `cursor_context is None` → Clipboard setzen + `trigger_paste()` (Cmd+V); Chrome's Blink-Renderer ignoriert Unicode-CGEvents für Web-`<input>`-Felder, aber Cmd+V geht durch Chrome's nativen Paste-Handler
- Nicht-Browser + `cursor_context is None` → Clipboard-Fallback, keine Events

`trigger_paste()` in `core/text_injector.py`: Socket → C-Launcher PASTE-Kommando, Fallback auf CGEvent Cmd+V (`kCGEventFlagMaskCommand` + kVK_ANSI_V=9).

**Ergebnis:**

- Chrome Web-Textfeld (cursor_context=None) → Clipboard + Cmd+V → Text erscheint; Clipboard enthält Text als Backup
- Chrome URL-Bar (cursor_context='') → direkte TYPE-Injektion (AX funktioniert für Omnibox)
- Chrome ohne aktives Textfeld → Cmd+V ohne Effekt; Text im Clipboard; Overlay zeigt Hinweis
- Finder/Desktop/PDF → nur Clipboard-Fallback
- Native Apps mit AX-Kontext → direkte TYPE-Injektion wie bisher

**Geänderte Dateien:**

- `core/text_delivery.py`
- `core/text_injector.py`
- `ui/menubar_app.py`

---

### 2026-04-25 — Fix: Injection-Gate via AX + Browser-Whitelist

**Status:** Überholt durch den Best-Effort-Delivery-Fix vom 2026-04-26. Die Annahme, dass TYPE-Events ohne Textfeld harmlos ins Leere gehen, war für die UX nicht ausreichend; Browser-Fallback kopiert den Text jetzt zusätzlich ins Clipboard und zeigt einen expliziten Hinweis.

**Problem:**

Nach Einführung des TYPE-Befehls wurde `inject_text()` immer aufgerufen — auch wenn kein Textfeld aktiv war. TYPE sendet Keyboard-Events an welches Element auch immer den Fokus hat und gibt immer "ok" zurück. Folge: Text wurde in zufällige Elemente (z.B. unsichtbare Felder in Chrome) geschrieben, oder Events gingen ins Leere — und der Clipboard-Fallback wurde nie ausgelöst.

**Damals eingeführter Fix (überholt):**

Zweistufiger Entscheidungsbaum in `ui/menubar_app.py`:

1. **AX bestätigt Textfeld** (`_cursor_context is not None`) → `inject_text()` — direktes Textfeld, TYPE funktioniert
2. **AX scheitert, aber bekannte Browser/Electron-App** (`_frontmost_bundle in BROWSER_ELECTRON_BUNDLES`) → `inject_text()` — diese Apps blockieren AX, nehmen aber Keyboard-Events an
3. **AX scheitert, unbekannte/native App** → `inject_text()` wird NICHT aufgerufen → Clipboard-Fallback + `show_copied()`

In `core/cursor_context.py`:

- Neue Konstante `BROWSER_ELECTRON_BUNDLES` (frozenset mit Bundle-IDs aller bekannten Chromium/Electron-Apps)
- Neue Funktion `get_frontmost_bundle_id()` → Bundle-ID der vordersten App
- `_begin_recording()` speichert Bundle-ID zeitgleich mit `_cursor_context` (vor dem Overlay, solange die User-App noch vorne ist)

**Damaliges Ergebnis (überholt):**

- ✓ Nativer App mit Textfeld: AX OK → inject
- ✓ Chrome/VS Code/Notion mit Textfeld: AX scheitert, Bundle-ID erkannt → inject via TYPE
- Überholt: Chrome/etc. ohne Textfeld braucht heute Sicherheitskopie ins Clipboard plus Overlay-Hinweis
- ✓ Finder/PDF/Desktop: AX scheitert, Bundle-ID unbekannt → Clipboard-Fallback

**Geänderte Dateien:**

- `core/cursor_context.py`
- `ui/menubar_app.py`

---

### 2026-04-25 — Feature: TYPE-Befehl im C-Launcher – Clipboard-freie Text-Injektion

**Problem:**

Nach der Cursor-Injektion erschien der diktierte Text trotzdem in der Zwischenablage (z. B. sichtbar in Raycast/Maccy). Ursache: Die PASTE-Strategie setzt den Text für ~1 Sekunde ins NSPasteboard — Clipboard-Manager erfassen jede Änderung sofort.

**Fix:**

Neues Socket-Protokoll-Kommando `TYPE<utf8text>`:

- **C-Launcher** (`build_app.py`): Neue Funktion `inject_type_utf8()` — konvertiert UTF-8-Bytes via CoreFoundation zu UniChar (UTF-16), sendet dann je Character zwei CGEvent-Keyboard-Events (Key Down + Key Up). Zeilenumbrüche werden als Return-Keycode 36 gesendet. Kein Clipboard-Zugriff.
- **Socket-Server** (`build_app.py`): `CMD_BUF` auf 64 KB erhöht; Lese-Schleife bis EOF statt einmaligem `recv()` — notwendig für variable Textlängen. Neuer Branch `strncmp(buf, "TYPE", 4)` ruft `inject_type_utf8(buf+4, total-4)` auf.
- **Python** (`core/text_injector.py`): Neue Funktion `_send_type_via_launcher(text)` sendet `b"TYPE" + text.encode("utf-8")` + `shutdown(SHUT_WR)`.
- **Injektions-Reihenfolge** in `_via_launcher_socket()`:
  1. `_send_type_via_launcher()` → kein Clipboard-Zugriff, kein Leak
  2. `_send_paste_via_launcher()` → Fallback mit temporärem Clipboard (wie bisher)

**Ergebnis:** Cursor-Injektion berührt die Zwischenablage nicht mehr. Clipboard-Manager sehen keinen VoiceFlow-Text.

**Tests:** 2 neue Tests (`test_via_launcher_socket_type_succeeds_without_touching_clipboard`, `test_via_launcher_socket_falls_back_to_paste_when_type_fails`); alle 17 Tests grün.

**Geänderte Dateien:**

- `build_app.py`
- `core/text_injector.py`
- `tests/test_text_injector.py`

---

### 2026-04-25 — Fix: Injection nicht von AX-Cursor-Erkennung abhängig machen

**Eigentliche Ursache (aus Logs):**

```
[CursorContext] Chrome: kAXFocusedUIElement err=-25212 → Electron-Fallback
[CursorContext] Chrome: AXManualAccessibility nicht setzbar (err=-25205)
[CursorContext] Chrome: kein Textelement gefunden → None
```

`get_context_before_cursor()` gibt `None` zurück für Google Chrome und teilweise Claude Desktop (Electron-Apps die AXManualAccessibility ablehnen). Der bisherige Code blockierte `inject_text()` komplett wenn `_cursor_context is None` — auch wenn ein aktives Textfeld vorhanden ist. Cmd+V via C-Launcher funktioniert aber auch ohne AX-Kontext, da die Injektion betriebssystemseitig an die fokussierte App gesendet wird.

**Fix:**

- `ui/menubar_app.py`: `if self._cursor_context is not None:` Guard entfernt. `inject_text()` wird jetzt immer aufgerufen.
- `_cursor_context` bleibt weiterhin für `should_capitalize()` (Großschreibung) zuständig — entkoppelt von der Injektionsentscheidung.
- Clipboard-Fallback (`copy_to_clipboard` + `show_copied()`) tritt nur noch ein wenn **alle** Injektionsstrategien scheitern (Socket, Keyboard-Typing, CGEvent-Direct) — nicht mehr bei AX-Fehlern.

**Ergänzende Fixes in `core/text_injector.py`:**

- `_via_launcher_socket` und `_via_cgevent_direct`: Clipboard wird jetzt **immer** restauriert, auch wenn der Paste-Schritt scheitert (vorher: kein Restore → Text verblieb im Clipboard).
- `_restore_clipboard_text("")`: Neuer `else`-Zweig ruft `NSPasteboard.clearContents()` auf wenn Clipboard vorher leer war.

**15 neue Tests in `tests/test_text_injector.py`** die alle Edge-Cases für Clipboard-Restore abdecken.

**Geänderte Dateien:**

- `ui/menubar_app.py`
- `core/text_injector.py`
- `tests/test_text_injector.py`

---

### 2026-04-25 — Fix: Clipboard immer restaurieren nach Injektion

**Problem:**

Zwei Bugs in `core/text_injector.py` führten dazu, dass der VoiceFlow-Text nach einer Cursor-Injektion dauerhaft in der Zwischenablage verblieb:

1. `_via_launcher_socket`: Wenn `_send_paste_via_launcher()` `False` zurückgab (Socket nicht verfügbar), wurde `_restore_clipboard_text` nie aufgerufen — der neue Text blieb im Clipboard, obwohl nichts eingefügt wurde.
2. `_restore_clipboard_text`: Wenn die Zwischenablage vor der Injektion **leer** war (`old_text == ""`), wurde die `if text:`-Bedingung nie erfüllt → `clearContents()` wurde nicht aufgerufen → VoiceFlow-Text blieb permanent im Clipboard.

**Fix:**

- `_via_launcher_socket` und `_via_cgevent_direct`: Clipboard wird jetzt **immer** restauriert (via `_restore_clipboard_text`), unabhängig davon ob der Paste erfolgreich war.
- `_restore_clipboard_text`: Neuer `else`-Zweig — wenn `old_text` leer war, wird `NSPasteboard.clearContents()` explizit aufgerufen.

**Geänderte Dateien:**

- `core/text_injector.py`

---

### 2026-04-25 — Fix: Clipboard-Fallback zuverlässig setzen

**Was geändert:**

Der Clipboard-Fallback setzt den Text jetzt auf dem AppKit-Main-Thread und verifiziert direkt, dass `NSPasteboard` wirklich den neuen Text enthält. Der automatische Paste-Pfad nutzt das Clipboard nur temporär und stellt danach den vorherigen Inhalt wieder her. Nur wenn keine Cursor-Injektion möglich ist, bleibt der erkannte Text dauerhaft in der Zwischenablage und das Copy-Overlay wird angezeigt.

**Geänderte Dateien:**

- `core/text_injector.py` — Main-Thread Clipboard-Set mit Rücklese-Verifikation; Paste-Pfade restaurieren den vorherigen Clipboard-Inhalt
- `ui/menubar_app.py` — Copy-Overlay nur im echten Clipboard-Fallback anzeigen
- `tests/test_text_injector.py` — erwartete Reihenfolge auf Socket-first-Strategie aktualisiert

**Nachbesserung 2026-04-25:** Clipboard-Restore nach Cursor-Injektion von 0,2s auf 1,0s verlängert, damit Ziel-Apps mit verzögerter Pasteboard-Verarbeitung den temporär gesetzten VoiceFlow-Text noch lesen können.

---

### 2026-04-24 — Feature: Clipboard-Fallback bei fehlendem Cursor-Kontext

**Was geändert:**

Wenn `get_context_before_cursor()` `None` zurückgibt (kein fokussiertes Textfeld erkannt), wird der transkribierte Text nicht injiziert, sondern in die Zwischenablage kopiert. Das Overlay zeigt dann „✓ Text in Zwischenablage kopiert" für 2,5 Sekunden an und blendet sich automatisch aus.

**Geänderte Dateien:**

- `ui/overlay.py` — neuer State `show_copied()` / `_set_copied()` (220px Pill, Blau-Glow, auto-hide 2.5s); `NSViewWidthSizable` auf Label für korrekte Breite bei Resize
- `core/text_injector.py` — neue Funktion `copy_to_clipboard(text)`
- `ui/menubar_app.py` — Pipeline-Weiche: `_cursor_context is None` → Clipboard + Overlay; sonst normaler Inject-Flow

---

### 2026-04-22 — Fix: Frühzeitiger RMS-Check (Whisper bei Stille überspringen)

**Problem:** Hotkey halten ohne Sprechen → Nachverarbeitung dauerte lange (Whisper-Inference lief auch auf reinem Mikrofon-Rauschen).

**Ursache:** Die `MIN_INPUT_RMS`-Prüfung in `_filter_result` lief erst NACH dem vollständigen Whisper-Call — zu spät.

**Eigentliche Ursache (aus Log):** `rms_in` der stillen Aufnahmen (0.0016–0.0040) liegt oberhalb von `MIN_INPUT_RMS = 0.001` — Threshold greift nicht. Whisper halluziniert (`'イン'`, `'Thank you.'`), `_filter_result` leert den Text, `_retry_reason` sieht `is_empty` → **Retry** → Whisper läuft ein zweites Mal. Das verdoppelt die Latenz.

**Fix 1:** `was_filtered: bool`-Flag in `TranscriptionResult` — wird in `_filter_result` auf `True` gesetzt wenn Text durch Halluzinations-/Blacklist-Filter geleert wird.

**Fix 2:** `_retry_reason` gibt `None` zurück wenn `was_filtered=True` oder `error` in `{no_speech_signal, empty_after_trim}` — kein Retry mehr bei erkannten Halluzinationen.

**Fix 3:** Früherkennung in `transcriber.transcribe()` vor `_transcribe_once`: wenn `0 < input_rms < MIN_INPUT_RMS`, sofort `error="no_speech_signal"` zurückgeben ohne Whisper aufzurufen.

**Fix 4 (Nachbesserung):** Non-Latin-Filter `len(alpha_chars) > 3` → `if alpha_chars:` — fängt jetzt auch einzelne japanische Zeichen wie `'ん'` (1 Alpha-Char), die vorher durchschlüpften.

**Fix 5 (Nachbesserung):** Neuer Filter in `_filter_result`: `avg_logprob < -1.1` bei ≤3 Wörtern → `was_filtered=True` — extrem niedriger logprob bei kurzer Ausgabe ist immer eine Halluzination, kein Retry sinnvoll.

**Geänderte Dateien:**

- `core/transcriber.py`

---

### 2026-04-22 — Design: Glow-Effekt für Overlay

**Was geändert:**

- Zwei-Layer-Struktur in `_build()`: `_glow_view` (hinter Pill, `masksToBounds=False` → Shadow sichtbar) + `_pill_view` (clippt Kinder, transparent)
- `_glow_view` trägt `_BG` Hintergrundfarbe + `CALayer` Shadow → farbiger Leuchteffekt außerhalb der Pill
- `_pill_view` trägt Border, `masksToBounds=True`, alle Content-Subviews (Fill, Bar, Ring, Label)
- `_set_glow(color, radius, opacity)` Helper für zustandsabhängige Glow-Farbe
- Recording: Rose-Glow (radius=18, opacity=0.80)
- Processing/Shrink-Ende: Blau-Glow (radius=12, opacity=0.55)
- Downloading: Blau-Glow (radius=12, opacity=0.50)
- Initializing: Blau-Glow (radius=10, opacity=0.40)
- Ready: Blau-Glow (radius=14, opacity=0.65)

**Geänderte Dateien:**

- `ui/overlay.py`

---

### 2026-04-21 — Design: History Window – Stats-Zahlen, Fenstergröße, Tests

**Was geändert:**

- `WIN_W` 860 → 1060, `WIN_H` 560 → 720 (Fenster deutlich größer, passt zum Screenshot)
- `STATS_W` 190 → 210 (breitere Stats-Sidebar)
- Stats-Zahlen: 26pt → 40pt Bold, Frame-Höhe 30 → 50, Zeichenbreite-Faktor 16 → 23
- Stats-Card-Höhe: `min(sh * 0.55, 220)` → `min(sh * 0.60, 300)`
- Min-Fenstergröße: 680×440 → 800×520
- 25 neue Tests in `tests/test_history_window.py`: Layout-Konstanten, `_fmt`, `_date_header`, `_compute_stats`, `_group_by_date`, `_read_entries`

**Geänderte Dateien:**

- `ui/history_window.py`
- `tests/test_history_window.py` (neu)

---

### 2026-04-22 — Fix: Mikrofon-Aufnahme in C-Launcher verlagert

**Problem:** `rms_in=0.0000` — macOS blockierte den Mikrofon-Zugriff von python3.12 still, auch wenn VoiceFlow.app unter Mikrofon-Berechtigungen aktiviert war. Ursache: VoiceFlow.app (C-Binary) hat die Berechtigung, aber python (Child-Prozess via fork) greift auf das Mikrofon zu. macOS prüft den tatsächlich anfragenden Prozess, nicht den Eltern-Prozess.

**Lösung:** CoreAudio-Aufnahme (AudioQueue) in den C-Launcher verschoben — analog zur Text-Injektion. Neues Socket-Protokoll: `START_RECORDING` / `STOP_RECORDING` liefert raw int16 PCM zurück. `audio_recorder.py` nutzt Socket-Modus wenn VoiceFlow.app läuft, sounddevice als Fallback für Terminal-Start.

**Geänderte Dateien:**

- `build_app.py` — C-Launcher: AudioToolbox, rec_start/rec_stop, Socket-Protokoll erweitert
- `core/audio_recorder.py` — Socket-Modus primär, sounddevice als Fallback

---

### 2026-04-22 — Fix: Text-Injektion via Socket zuerst (python braucht keine Accessibility)

**Problem:** `venv/bin/python3.12` brauchte plötzlich Accessibility-Berechtigung, obwohl der C-Launcher (VoiceFlow.app) diese Berechtigung haben sollte.

**Ursache:** `_via_keyboard_typing` (CGEventPost direkt aus python) war die erste Option in der Fallback-Kette. Da `CGEventPost` ohne Accessibility-Berechtigung keine Exception wirft, sondern still fehlschlägt, gab die Funktion immer `True` zurück — der Socket-Weg (C-Launcher mit VoiceFlow.app's Accessibility) wurde nie erreicht.

**Fix:** Reihenfolge geändert: Socket zuerst → Keyboard-Typing als Fallback (Terminal-Start).

**Geänderte Dateien:**

- `core/text_injector.py`

---

### 2026-04-22 — Fix: CGEventTap Callback – NSInternalInconsistencyException bei Fn-Events

**Problem:** `Fn+Shift` wurde nicht erkannt. Log zeigte: `[Hotkey] Callback-Fehler: NSInternalInconsistencyException - Invalid parameter not satisfying: _type > 0 && _type <= kCGSLastEventType`

**Ursache:** `NSEvent.eventWithCGEvent_(event)` wurde für alle Event-Typen aufgerufen. Bestimmte System-Events (u.a. Fn-Taste) haben einen internen CGS-Typ der außerhalb des gültigen NSEvent-Bereichs liegt → Exception. Vorher wurde bei Exception `flags = 0` gesetzt und `_fn_down = False` — damit wurde jede Fn-Betätigung als "losgelassen" interpretiert.

**Fix:** `NSEvent.eventWithCGEvent_` nur noch innerhalb des `kCGEventFlagsChanged`-Zweigs aufrufen. Bei Exception den Tastenzustand unverändert lassen (`pass`) statt auf False zurückzusetzen.

**Geänderte Dateien:**

- `core/hotkey_manager.py`

---

### 2026-04-21 — Fix: Hotkey CGEventTap (Fn+Shift funktioniert nicht mehr in .app-Bundle)

**Problem:** Fn+Shift wurde nicht erkannt wenn die App über das VoiceFlow.app-Bundle gestartet wurde. Kein Overlay, keine Aufnahme. Im Debug-Log: `Fn=False Shift=False` dauerhaft.

**Ursache:** `CGEventSourceKeyState` mit `kCGEventSourceStateHIDSystemState` benötigt auf macOS 15 (Sequoia) implizit die _Input Monitoring_ Berechtigung (`kTCCServiceListenEvent`). Beim Start aus dem Terminal erbte der Python-Prozess die Berechtigung von Terminal.app. Das VoiceFlow.app-Bundle hat diese Berechtigung nicht geerbt → API lieferte stillschweigend `False` für alle Keys.

**Lösung:** `core/hotkey_manager.py` auf **CGEventTap** (`kCGEventTapOptionListenOnly`) umgeschrieben. CGEventTap:

- Löst macOS Input Monitoring Permission-Dialog automatisch aus
- Erkennt Fn+Shift über `kCGEventFlagsChanged` + `NSFnKeyMask` / `NSShiftKeyMask`
- Fallback auf alten Polling-Ansatz wenn CGEventTap nicht erstellt werden kann

**Geänderte Dateien:**

- `core/hotkey_manager.py`

---

### 2026-04-19 — Fix: Ellipsis-Normalisierung, Wort-Repetition-Filter, Non-Latin-Script-Filter

**Probleme (aus Log):**

1. `"No, I'm addicted to..."` → `"No, I'm addicted to. . ."` — drei einzelne Punkte mit Leerzeichen
2. `"berechnung berechnung berechnung berechnung"` — Whisper-Wort-Repetition nicht gefiltert, LLM kapitalisierte sie sogar
3. `"ステッシュッ"` mit logprob=-1.70 — japanische Zeichen wurden in eine DE/EN-App injiziert

**Ursachen:**

1. `_SPACE_AFTER_PUNCT` Regex `([,.;:!?])` enthielt `.` — jeder Punkt in `...` wurde einzeln als Satzende behandelt und mit Leerzeichen versehen
2. `_has_repetition_loop` prüft Ngrams erst ab `len(words) >= 8` und nur bei >4 Vorkommen — 4× dasselbe Wort in Folge (z.B. "berechnung x4") wurde nicht erkannt
3. Kein Filter für Non-Latin Script — Whisper halluziniert bei schlechtem Audio gelegentlich Katakana/CJK, auch nach Retry

**Fixes:**

- `core/text_normalizer.py` — `_SPACE_AFTER_PUNCT`: `.` nur matchen wenn nicht von weiterem `.` umgeben: `(?<!\.)\.(?!\.)` — `...` bleibt unverändert, einzelner Satzpunkt funktioniert weiterhin
- `core/transcriber.py` — `_has_repetition_loop`: neues Muster für konsekutive Einzelwort-Wiederholung: `\b(\w{4,})\b(?:\W+\1\b){2,}` — fängt 3+ Vorkommen desselben Worts hintereinander
- `core/transcriber.py` — `_filter_result`: neuer Non-Latin-Script-Filter — wenn >50% der Buchstaben non-ASCII (ord ≥ 256) sind, wird der Text verworfen; deckt Katakana, CJK, etc. ab

**Geänderte Dateien:**

- `core/text_normalizer.py`
- `core/transcriber.py`

---

### 2026-04-15 — Fix: Modellwechsel Absturz + fehlendes Download-Fenster

**Problem:** Beim Wechsel zwischen `large-turbo` und `large` (oder umgekehrt) stürzte die App ab und das Download-Fenster erschien nicht, wenn das Zielmodell noch nicht heruntergeladen war.

**Ursache 1 — `is_model_cached` falsch-positiv:**
HuggingFace Hub legt die Verzeichnisstruktur (inkl. leerer Snapshot-Hash-Unterordner) direkt beim Download-Start an — noch bevor die eigentlichen Modelldateien ankommen. `any(snapshots.iterdir())` lieferte daher `True` für ein leeres/unvollständiges Modell → `_download_model` wurde nie aufgerufen → kein Download-Fenster.

**Ursache 2 — kein Recovery bei fehlgeschlagenem Warmup:**
`transcriber.warmup()` fing Fehler zwar ab (try/except), gab aber kein Ergebnis zurück. `_warmup_current` wusste nicht ob der Load erfolgreich war und startete weder einen Retry noch einen Re-Download — die App blieb in einem inkonsistenten State hängen.

**Ursache 3 — kein Guard gegen Doppel-Switch:**
Schnelles Klicken während eines laufenden Downloads oder der Init-Phase konnte einen zweiten Switch auslösen.

**Fixes:**

- `core/model_manager.py` — `is_model_cached` prüft jetzt ob mindestens eine echte Gewichtsdatei (`.npz`, `.safetensors`, `.bin`, ≥ 1 MB) im Snapshot vorhanden ist, nicht nur ob das Verzeichnis existiert
- `core/transcriber.py` — `warmup()` gibt `bool` zurück (`True` = erfolgreich, `False` = Fehler)
- `ui/menubar_app.py` — `_warmup_current`: wenn `warmup()` False zurückgibt, wird `_download_model` erneut aufgerufen (Re-Download der unvollständigen Dateien)
- `ui/menubar_app.py` — `_set_model`: Guard am Anfang — Modellwechsel wird ignoriert wenn State `downloading` oder `initializing` ist

**Geänderte Dateien:**

- `core/model_manager.py`
- `core/transcriber.py`
- `ui/menubar_app.py`

---

### 2026-04-15 — Phonetische Substitution: Temperature-Retry + Prompt-Fix

**Problem:** "halluziniert" → "emulsioniert" (Whisper, logprob=-0.66), dann "emulsioniert" → "emulsiert" (LLM normalisierte non-standard Verbform — double-wrong).

**Fehler-Taxonomie aus Logs:**

- Klasse 1 Phonetische Substitution: seltene Verben werden durch häufigere phonetisch ähnliche ersetzt (logprob -0.45 bis -0.70) — confident falsch, overlapping mit korrekten Transkriptionen
- Klasse 2 Englische Fachbegriffe: gelöst durch language=auto
- Klasse 3 Sprachverwechslung: kurze Utterances mit auto können en/de verwechseln
- Klasse 4 Strukturelles Rewriting: logprob -0.70 bis -0.80, jetzt von Retry erfasst

**Fixes:**

- Retry-Threshold: -0.75 → -0.60 — fängt "emulsioniert"-Fall (-0.66) und ähnliche
- Temperature-Retry: bei `low_logprob`-Retry im balanced-Profil wird `temperature=(0.0, 0.2)` verwendet statt nur 0.0 — weichere Wahrscheinlichkeitsverteilung gibt seltenen korrekten Wörtern eine Chance; `condition_on_previous_text=False` bleibt (verhindert Halluzinationen)
- Minimal-Prompt: explizit verboten Verbstämme/Konjugationen zu verändern — verhindert LLM double-wrong

**Geänderte Dateien:**

- `core/transcriber.py` — Threshold, `_build_decode_kwargs(temperature_retry)`, `_transcribe_once(temperature_retry)`
- `core/prompts.py` — minimal level: Verbstamm-Verbot
- `tests/test_transcriber.py` — 2 neue Tests, Grenzwert-Test auf -0.60 aktualisiert

---

### 2026-04-15 — Stille-Halluzinationsfilter (Transcriber)

**Problem:** Mikrofon 2-3s gehalten ohne Sprechen → Output `"Thank you."` (klassische Whisper-Halluzination auf Stille). `no_speech_prob=0.00` — Whisper war paradoxerweise zuversichtlich, also griff der bestehende no_speech-Filter nicht.

**Ursachen:**

- `input_rms=0.0025` — reines Mikrofon-Rauschen, kein Sprachsignal. Kein Filter prüfte die Eingangsenergie.
- `_has_repetition_loop` im Transcriber prüfte nur Wort-Ngrams, nicht Zeichen-Muster → ギギギギ-Halluzinationen (einzelnes Zeichen, ein "Wort") wurden nicht erkannt.

**Fixes:**

- `MIN_INPUT_RMS = 0.006`: neuer Filter in `_filter_result` — wenn `input_rms < 0.006`, sofort verwerfen (kein Sprachsignal). Aus den Logs: Stille=0.0025, echte Sprache=0.028+
- `_has_repetition_loop` um Zeichen-Regex erweitert: `(.{1,6})\1{8,}` — fängt ギギギ und LMLMLM
- `"thank you"` / `"thank you."` zur Blacklist hinzugefügt (sekundäre Absicherung)

**Geänderte Dateien:**

- `core/transcriber.py`
- `tests/test_transcriber.py` — 9 neue Tests

---

### 2026-04-15 — Performance-Optimierung: level-aware num_predict + num_ctx (Ollama)

**Ziel:** LLM-Latenz für 2-3-Satz-Diktat reduzieren ohne Qualitätsverlust.

**Änderungen:**

- `_num_predict(input_words, level)` — level-abhängiges Token-Limit statt pauschales `input_words * 3`:
  - `minimal`: `max(40, input_words + 12)` — Korrektur-only, Output ≈ Input-Länge
  - `soft`: `max(50, input_words * 1.3)`
  - `medium`: `max(60, input_words * 1.8)`
  - `high`: `max(80, input_words * 2)`
  - Beispiel 25 Wörter/minimal: 90 Tokens → 37 Tokens (~59% weniger Generierungsarbeit)
- `OLLAMA_NUM_CTX` 1024 → 768 — System-Prompt ~300 T + 2-3 Sätze ≈ 400 T — kleinerer KV-Cache
- `_call_ollama` nimmt jetzt `level` entgegen und leitet es an `_num_predict` weiter

**Geänderte Dateien:**

- `core/ollama_processor.py`
- `tests/test_ollama_processor.py` — Mock-Lambda auf `**kwargs` erweitert

---

### 2026-04-15 — Performance-Fix & Repetitions-Loop-Schutz (Ollama Post-Processor)

**Problem 1:** Post-Processing dauerte zu lange.
**Ursachen:**

- Kein `num_ctx` gesetzt → Ollama lief mit Standard 2048–4096 Tokens KV-Cache, auch für 1–3-Satz-Diktat-Texte
- Kein `num_predict` Limit → Modell konnte mehr Tokens generieren als nötig
- `keep_alive: "10m"` → Modell wurde nach kurzer Pause aus dem RAM entladen

**Problem 2:** Sporadischer Output wie `"Teile des Textes... LMLMLMLMLMLMLMLM..."`
**Ursache:**

- `temperature: 0` (greedy decoding) + **kein `repeat_penalty`** → klassischer Repetitions-Loop ohne Ausweg
- `_has_repetition_loop()` fehlte in der LLM-Output-Validierung (war nur im Whisper-Transcriber)

**Lösung:**

- `OLLAMA_NUM_CTX = 512` → ausreichend für kurze Diktat-Korrekturen, ~3–4× schnellere Inferenz
- `num_predict = max(60, input_words * 3)` → dynamisches Token-Limit pro Anfrage
- `repeat_penalty: 1.15` + `repeat_last_n: 64` → bricht Repetitions-Loops bei greedy decoding
- `keep_alive: "30m"` → Modell bleibt länger im RAM (von 10m erhöht)
- `_has_repetition_loop()` in `llm_post_processor._validate_output` → fängt Loops bei allen Enhancement-Levels ab, inkl. Zeichenmuster-Regex für "LMLMLM..."-Typ

**Geänderte Dateien:**

- `core/ollama_processor.py` — neue Konstanten, `_call_ollama` und `warmup` aktualisiert
- `core/llm_post_processor.py` — `_has_repetition_loop()` hinzugefügt, in `_validate_output` eingehängt

---

## Abgeschlossen (Archiv)

### 2026-04-09 — Frontend-Redesign v2: Void Signal Aesthetic

**Was geändert:** Vollständiges visuelles Redesign beider UI-Komponenten — neues Farbsystem, neue Waveform-Logik, neue Proportionen.

**Design-Richtung:** Void Signal — near-black (`#0A0A0F`), Rose-Akzent (`#F2667A`) für Aufnahme/Interaktion, Sky Blue (`#66CCFF`) für Informations-/Fortschritts-Zustände, kühles Off-White statt warmes Off-White.

**overlay.py:**

- Neue Palette: `_BG` (near-black, kühler Blau-Shift), `_ROSE` für Waveform/Recording, `_BLUE` / `_BLUE_FILL` für Download/Init/Ready
- Pill-Höhe: 38px → 34px, Radius: 19 → 17 (schlanker, präziser)
- Waveform: 2 Wellen (amber) → 3 Harmonische in Rose — Grundwelle (1.6pt) + zweite Harmonische (38% Opazität, 0.8pt) + dritte Harmonische (14% Opazität, Gegenphase, 0.5pt)
- Rahmen: reines Weiß 10% → Sky Blue 10% (thematisch stimmig)
- Fill-Bar: Amber → Sky Blue
- Text-Farbe: warmes Off-White `(0.95, 0.94, 0.90)` → kühles Off-White `(0.87, 0.90, 0.95)`
- Ready-State: Amber → Sky Blue
- Download-Text auf Fill: dunkelnavyblau statt dunkelbraun

**history_window.py:**

- Hintergrund: `(0.09, 0.09, 0.11)` → `(0.04, 0.04, 0.06)` — deutlich tiefer/dunkler
- Sidebar-BG: `(0.07, 0.07, 0.09)` → `(0.03, 0.03, 0.05)`
- Text: kühles Off-White `(0.87, 0.90, 0.95)` statt warmem
- Stats-Zahlen: Amber → Sky Blue, Schrift von Bold 34pt → Semibold 32pt (raffinierter)
- Icon-Sidebar: Amber aktiver Hintergrund → Blue Dim; aktive Icon-Tint: Amber → Sky Blue
- Row-Press-Feedback: Amber-Ton → Rose-Ton (unterscheidet sich klar von Hover)
- Key-Pills: dunklerer Hintergrund `(0.14, 0.15, 0.18)`, weißer Border 10%
- Separator-Opazität: 6% → 5% (subtiler)

**Geänderte Dateien:**

- `ui/overlay.py`
- `ui/history_window.py`

---

### 2026-04-09 — Frontend-Redesign: Dark Studio Aesthetic

**Was geändert:** Komplettes visuelles Redesign beider UI-Komponenten mit dem frontend-design Skill.

**Design-Richtung:** Refined Dark Studio — tiefes Anthrazit (`#17171c`), warmer Amber-Akzent (`#FF9E1A`), keine generischen macOS-Defaults (kein system blue, kein forced light mode).

**overlay.py:**

- Neue Farbpalette: `_BG` (dunkel-anthrazit, 94% opak) + `_AMBER` als Akzentfarbe statt generischem Blau
- Doppelte Wellenform: Haupt-Welle in Amber + Echo-Welle halbtransparent versetzt
- Subtiler Rahmen (0.5pt, 10% weiß) für Tiefenwirkung
- "Modell bereit"-State zeigt Text in Amber statt weiß
- Download-Fill in Amber; Label-Farbe wechselt je nach Fill-Fortschritt (dunkel auf hellem Hintergrund)

**history_window.py:**

- Vollständiges Dark Theme statt `NSAppearanceNameAqua` → `NSAppearanceNameDarkAqua`
- Eigene Farbpalette (nicht mehr system accent color): warmer Weißton `(0.95, 0.94, 0.90)`, Amber für Zahlen
- Stats-Sidebar: Caption uppercase+klein oben, große Zahl in Amber unten — mehr Impact
- Icon-Sidebar: amber-getönter aktiver Hintergrund statt system accent
- Key-Pills: dunkleres Grau mit feinem Rahmen (0.5pt)
- Fenster-Titel: "VoiceFlow — Verlauf" statt nur "Verlauf"

**Geänderte Dateien:**

- `ui/overlay.py`
- `ui/history_window.py`

---

### 2026-04-07 — Fix: Großschreibung nach `.!?` mit Unicode-Whitespace im Cursor-Context

**Problem:** Wenn die App nach dem Satzzeichen einen Unicode-Whitespace-Charakter hinterließ (z.B. U+00A0 Non-Breaking Space), gab `should_capitalize()` fälschlicherweise `False` zurück — das Enforcement-Block lowercased daraufhin den ersten Buchstaben aktiv.

**Ursache:** `context.rstrip(" \t")` entfernte nur ASCII-Space und Tab, nicht alle Unicode-Whitespace-Zeichen.

**Lösung:** `context.rstrip(" \t")` → `context.rstrip()` — Python's `str.rstrip()` ohne Argument verwendet `str.isspace()` und entfernt alle Unicode-Whitespace-Zeichen.

**Geänderte Dateien:**

- `core/cursor_context.py` — Zeile 342: `rstrip(" \t")` → `rstrip()`

---

### 2026-04-06 — Halluzinations-Filter: Nur-Satzzeichen-Output

**Problem:** Whisper erzeugte bei 3-4 Sekunden Stille/Hintergrundgeräuschen das Zeichen `"!"` — die `no_speech_prob` lag dabei knapp unter dem 0.5-Schwellwert, sodass der bestehende Filter nicht griff.

**Ursache:** Whisper halluziniert Satzzeichen wie `"!"`, `"..."`, `"…"` wenn es Geräusche erkennt, aber keine eigentliche Sprache transkribieren kann.

**Lösung:** Neuer Filter am Ende von `transcribe()`: wenn der Text nach Entfernen aller Nicht-Wort-Zeichen leer ist (also kein einziger Buchstabe/Ziffer enthalten), wird `""` zurückgegeben.

**Geänderte Dateien:**

- `core/transcriber.py` — Regex-Prüfung `re.sub(r'[^\w]', '', text)` nach der Blacklist

---

### 2026-04-06 — LLM Post-Processing v2: erweiterter Korrektur-Scope

**Problem:** Bisheriger System-Prompt korrigierte ausschließlich phonetische Fehler bei Eigennamen — Satzzeichen, Groß-/Kleinschreibung und Grammatik wurden nicht angefasst.

**Lösung:**

- `_SYSTEM_PROMPT_BASE` komplett neu: jetzt explizit erlaubt: Satzzeichen setzen, deutsche Nomen großschreiben, Eigennamen großschreiben, phonetische Korrekturen
- Explizit verboten: Wörter entfernen/hinzufügen, Satzbau ändern — der gesprochene Stil bleibt erhalten
- Few-Shot-Beispiele für alle erlaubten Korrekturen ergänzt (Komma, Punkt, Fragezeichen, Nomen-Großschreibung)
- `_validate_output()` überarbeitet: prüft jetzt **Wortanzahl** (max. ±1 Wort Abweichung) statt reiner Zeichenlänge — fängt Halluzinationen zuverlässiger ab ohne legitime Korrekturen zu blockieren
- Zeichen-Ratio-Schwellwert von 0.55 → 0.60 auf bereinigtem Text (ohne Satzzeichen)

**Geänderte Dateien:**

- `core/llm_post_processor.py`

---

### 2026-04-06 — Cursor-Kontext für Electron-Apps (AXManualAccessibility)

**Problem:** Claude Code, VS Code und andere Electron-Apps blockierten `kAXFocusedUIElementAttribute` (`err=-25212`). Cursor-Kontext war für diese Apps nicht lesbar → Großschreibung wurde falsch gehandhabt.

**Untersuchung:**

- AX Tree Traversal zeigte: alle Elemente mit `val=''`, `n_chars=0` → Chromium exponiert AX-Baum nicht standardmäßig
- Entdeckung: `AXManualAccessibility`-Attribut (Chromium-intern) war `False`
- `AXEnhancedUserInterface` war bereits `True` (reicht allein nicht)

**Lösung:** `AXManualAccessibility=True` per `AXUIElementSetAttributeValue` setzen → Chromium aktiviert vollständigen AX-Baum inkl. `kAXValue` und `kAXSelectedTextRange`

**Geänderte Dateien:**

- `core/cursor_context.py` — 3-stufige Strategie: Direct → Electron (AXManualAccessibility) → Tree-Traversal; Clipboard-Trick komplett entfernt
- `core/llm_post_processor.py` — `capitalize: Optional[bool]` statt `bool`; `None` = "Großschreibung nicht anfassen"
- `ui/menubar_app.py` — `capitalize` direkt weitergeben (kein `True`-Fallback mehr)

**Ergebnis:** Cursor-Kontext funktioniert nun für native Apps UND Electron-Apps ohne Clipboard, ohne Keyboard-Simulation, ohne visuellen Effekt. PID-Caching verhindert wiederholtes Setzen.

---

### 2026-04-06 — Automatisches Vokabular-Lernen (VocabLearner)

**Problem:** Whisper machte wiederholt dieselben Fehler bei Eigennamen/Tech-Begriffen (z.B. "opener eye" statt "OpenAI"). Manuelle Korrekturen waren unpraktisch.

**Lösung:** Automatischer Lernkreislauf:

1. LLM korrigiert Whisper-Output
2. `VocabLearner` vergleicht Original vs. Korrektur via `difflib.SequenceMatcher`
3. Unterschiede werden in `vocab_cache.json` gespeichert
4. Nächste Whisper-Aufnahme bekommt gelernte Begriffe als `initial_prompt`
5. Bei deaktiviertem LLM: `apply_learned_corrections()` wendet Cache direkt an

**Schutzregel:** Nur CamelCase/Abkürzungen/alphanumerische Begriffe werden gelernt (`_looks_like_proper_term`), verhindert Cache-Poisoning durch LLM-Halluzinationen.

**Geänderte/neue Dateien:**

- `core/vocab_learner.py` — NEU: VocabLearner Klasse, extract_corrections, apply_learned_corrections
- `core/transcriber.py` — `vocabulary` Parameter, `build_initial_prompt()`, `update_vocabulary()`
- `ui/menubar_app.py` — VocabLearner integriert, `_learn_and_update_vocab()` Methode

---

### 2026-04-06 — LLM Post-Processing verbessert

**Problem:** LLM halluzinierte Antworten statt zu korrigieren ("Kaptos ist korrekt großgeschrieben. Danke."). Kein Sicherheitsnetz gegen fehlerhafte Outputs.

**Lösung:**

- `_SYSTEM_PROMPT_BASE` mit Few-Shot-Beispielen ersetzt (zeigt exakt was erlaubt/verboten ist)
- `_validate_output()` als Sicherheitsnetz: `SequenceMatcher`-Ratio < 0.55 oder Länge > 1.3× → Fallback auf Original
- `capitalize: Optional[bool]` — drei Zustände: Satzanfang / mid-sentence / unbekannt

**Geänderte Dateien:**

- `core/llm_post_processor.py`

---

### 2026-04-06 — LLM standardmäßig aktiviert

**Änderung:** `llm_post_processing: bool = True` (war `False`)

**Geänderte Dateien:**

- `settings/app_settings.py`

---

## Aktueller Stand (2026-04-06)

- ✅ Push-to-Talk mit `Fn + Shift`
- ✅ Whisper-Transkription (lokal, Apple Silicon)
- ✅ LLM-Korrektur (Phi-4-mini / Qwen 2.5, lokal)
- ✅ Automatisches Vokabular-Lernen
- ✅ Cursor-Kontext für native Apps UND Electron-Apps
- ✅ Korrekte Groß/Kleinschreibung je nach Cursor-Position
- ✅ Text-Injektion via CGEventPost
- ✅ Menubar-UI mit Statistik, Modell-/Sprachauswahl
- ✅ Wort-Statistiken (heute / 7 Tage / gesamt)

---

## Geplant / Offen

### 🔄 Swift-Migration (Branch: `swift-migration`)

Migration des gesamten Stacks von Python/C-Launcher auf Swift + WhisperKit.

**Motivation:** Echte `.app` ohne C-Launcher-Hack, native Permissions, ~20 MB Bundle statt
1,1 GB venv, triviales Homebrew Cask, bessere Startup-Zeit.

**Phasendokumente:** [`docs/swift-migration/`](docs/swift-migration/README.md)

| Phase                                              | Titel                          | Dauer  | Status    |
| -------------------------------------------------- | ------------------------------ | ------ | --------- |
| [1](docs/swift-migration/phase-1-foundation.md)    | Xcode-Projekt & Foundation     | 1–2 Wo | ✅ fertig |
| [2](docs/swift-migration/phase-2-audio-input.md)   | Audio & Hotkey                 | 2–3 Wo | ✅ fertig |
| [3](docs/swift-migration/phase-3-whisper.md)       | WhisperKit-Integration         | 3–4 Wo | ⏳ offen  |
| [4](docs/swift-migration/phase-4-llm.md)           | LLM Enhancement                | 3–4 Wo | ⏳ offen  |
| [5](docs/swift-migration/phase-5-text-delivery.md) | Text Delivery & AX API         | 3–4 Wo | ⏳ offen  |
| [6](docs/swift-migration/phase-6-ui.md)            | UI (MenuBar, Overlay, History) | 3–4 Wo | ⏳ offen  |
| [7](docs/swift-migration/phase-7-distribution.md)  | Distribution & Cleanup         | 1–2 Wo | ⏳ offen  |

**Gesamtschätzung:** 16–23 Wochen

### Phase 2 — 2026-05-15: Audio & Hotkey implementiert

**Neu/geändert:**

- `VoiceFlow/Input/HotkeyManager.swift` — CGEventTap für Fn+Shift (listen-only), Fn-Bit 0x800000, Callbacks auf Main-Thread; Polling-Fallback falls Input Monitoring nicht granted
- `VoiceFlow/Audio/AudioRecorder.swift` — AVAudioEngine actor, 16 kHz/Float32, AVAudioConverter für Nicht-16kHz-Geräte, vDSP RMS; `prepare()` hält Engine warm beim App-Start
- `VoiceFlow/UI/OverlayLevelMapper.swift` — Portierung von Python VisualLevelMapper: adaptiver Noise-Floor, Peak-Tracking, perceptual pow(0.55)-Scaling, 9 Sinus-modulierte Balken

---

### Sonstige offene Punkte

- [ ] Cursor-Kontext für weitere Electron-Apps validieren (VS Code, Notion, Chrome)
- [ ] Satzzeichen-Erkennung verbessern (Komma per Sprache einfügen)
- [ ] Mehrsprachige Dokumente besser unterstützen (DE/EN Mix)
- [ ] Vocab-Cache UI: anzeigen, löschen einzelner Einträge aus der Menubar
- [ ] Performance: Whisper-Ladezeit beim ersten Start reduzieren

---

## Bekannte Einschränkungen

| Problem                                          | Ursache                           | Workaround                                |
| ------------------------------------------------ | --------------------------------- | ----------------------------------------- |
| Electron-Apps ohne `AXManualAccessibility`       | App muss Chromium-based sein      | Strategie 3 (Tree-Traversal) als Fallback |
| LLM erste Aktivierung langsam                    | Modell muss in RAM geladen werden | Warmup beim App-Start                     |
| Whisper bei kurzen Aufnahmen (<1s) unzuverlässig | Zu wenig Audio-Kontext            | Mindestens 1-2 Sekunden sprechen          |
