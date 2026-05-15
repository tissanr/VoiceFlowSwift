# Phase 4 — LLM Enhancement

> **Dauer:** 3–4 Wochen | **Vorgänger:** Phase 3 | **Nachfolger:** Phase 6

## Ziel

Whisper-Output lokal per LLM verbessern — Grammatik, Zeichensetzung, Eigennamen — mit mlx-swift
oder Ollama als Backend, identisches Qualitätsniveau wie bisher.

## Warum jetzt

Kann parallel zu Phase 5 (Text Delivery) laufen sobald Phase 3 fertig ist. Der LLM-Output ist
für die UI (Phase 6) erforderlich aber nicht für die Text-Injection-Logik.

---

## Komponenten

### 4.1 Prompts

**Python-Quelle:** `core/prompts.py` (106 Zeilen)

Reine String-Konstanten — direkte Portierung.

```swift
// Sources/VoiceFlow/LLM/Prompts.swift
enum EnhancementLevel: String, Codable, CaseIterable {
    case minimal, soft, medium, high
}

enum EnhancementStyle: String, Codable, CaseIterable {
    case concise, explanatory, formal, casual
}

struct Prompts {
    static func systemPrompt(level: EnhancementLevel, style: EnhancementStyle, vocabulary: [String]) -> String
    static func userPrompt(text: String, capitalize: Bool?) -> String
}
```

---

### 4.2 TextNormalizer

**Python-Quelle:** `core/text_normalizer.py` (~200 Zeilen)

Keine Abhängigkeiten, reine Regex-Transformation.

```swift
// Sources/VoiceFlow/Text/TextNormalizer.swift
struct TextNormalizer {
    /// Gesprochene Satzzeichen → Symbole ("Punkt" → ".", "Komma" → ",")
    static func normalize(_ text: String) -> String
}
```

- Swift Regex Literals (`/pattern/`) für alle Ersetzungsregeln
- Ellipsis-Fix: `(?<!\.)\.(?!\.)` — identisch mit Python-Original
- Wort-Repetitions-Filter: `\b(\w{4,})\b(?:\W+\1\b){2,}`

---

### 4.3 PostProcessor (Listen-Erkennung)

**Python-Quelle:** `core/post_processor.py` (~120 Zeilen)

```swift
// Sources/VoiceFlow/Text/PostProcessor.swift
struct PostProcessor {
    /// Erkennt "erstens / zum ersten / Punkt eins / firstly" und formatiert als Liste
    static func process(_ text: String) -> String
}
```

---

### 4.4 LLMPostProcessor (mlx-swift)

**Python-Quelle:** `core/llm_post_processor.py` (~400 Zeilen)

```swift
// Sources/VoiceFlow/LLM/LLMPostProcessor.swift
import MLX
import MLXLLM

actor LLMPostProcessor {
    func warmup() async throws
    func process(
        text: String,
        level: EnhancementLevel,
        style: EnhancementStyle,
        capitalize: Bool?,
        vocabulary: [String]
    ) async -> String   // gibt Original zurück bei Fehler
}
```

**mlx-swift API-Mapping:**

```swift
// Python (mlx-lm):
model, tokenizer = mlx_lm.load("mlx-community/Qwen2.5-1.5B-Instruct-4bit")
response = mlx_lm.generate(model, tokenizer, prompt=prompt, max_tokens=100)

// Swift (mlx-swift):
let config = ModelConfiguration(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
let (model, tokenizer) = try await LLMModel.load(configuration: config)
let result = try await LLMModel.generate(
    model: model, tokenizer: tokenizer,
    prompt: prompt, maxTokens: 100
)
```

**KV-Cache (System-Prompt Pre-filling):**

- Python hat manuelles KV-Cache-Management via `make_prompt_cache` + `trim_prompt_cache`
- mlx-swift: prüfen ob `KVCache`-Protokoll in der aktuellen Version verfügbar ist
- Fallback: System-Prompt bei jedem Call neu verarbeiten (einfacher, minimal langsamer)

**Output-Validierung** (direkt portiert):

```swift
private func validateOutput(_ output: String, input: String) -> Bool {
    // 1. Wortanzahl: max ±1 Wort Abweichung
    // 2. Zeichenlänge (ohne Satzzeichen): Ratio >= 0.60
    // 3. Repetitions-Loop: (.{1,6})\1{8,} oder \b(\w{4,})\b(?:\W+\1\b){4,}
    // 4. Meta-Kommentar: beginnt mit "Hier ist" / "Sure," / "As an AI" → verwerfen
}
```

**Modell-Download:**

- Nutzt `ModelDownloader` aus Phase 3 (HF REST API)
- Modelle: `mlx-community/Qwen2.5-1.5B-Instruct-4bit` (default), `Qwen2.5-3B`, `Phi-4-mini-4bit`

**Risiken:**

- mlx-swift ist jünger als mlx-lm — API kann sich zwischen Releases ändern. Version pinnen.
- KV-Cache-API in mlx-swift evtl. noch nicht öffentlich stabil → Warmup-Performance prüfen
- Modell-Loading auf Background-Thread, UI muss "LLM lädt..." zeigen (Phase 6 koordinieren)

---

### 4.5 OllamaProcessor

**Python-Quelle:** `core/ollama_processor.py` (~200 Zeilen)

```swift
// Sources/VoiceFlow/LLM/OllamaProcessor.swift
actor OllamaProcessor {
    func warmup() async throws
    func process(text: String, level: EnhancementLevel, style: EnhancementStyle) async -> String
}
```

**URLSession-Implementierung:**

```swift
// POST http://localhost:11434/api/chat
struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool = false
    let options: OllamaOptions
}

// Streaming via URLSession.bytes(for:) wenn stream: true
```

- Timeout: 5 s connect, 30 s response (identisch Python)
- `keep_alive: "30m"` im Request-Body
- `num_ctx: 768`, dynamisches `num_predict` basierend auf Input-Wortanzahl

---

## Swift-Frameworks & Bibliotheken

| Framework                   | Zweck                                             |
| --------------------------- | ------------------------------------------------- |
| mlx-swift (SPM)             | LLM-Inferenz (Qwen, Phi)                          |
| MLXLLM (Teil von mlx-swift) | Model-Loading, Token-Generation                   |
| Foundation URLSession       | Ollama HTTP-Client                                |
| Swift Regex                 | TextNormalizer, PostProcessor, Output-Validierung |

---

## Done-Kriterium

- [ ] `LLMPostProcessor.process("das ist ein test")` gibt korrigierten Text zurück ("Das ist ein Test.")
- [ ] Ollama-Client sendet erfolgreich Request an lokales Ollama und verarbeitet Response
- [ ] Output-Validierung verwirft Halluzinationen (Test mit "Hier ist die korrigierte Version:")
- [ ] Warmup schlägt still fehl wenn kein Modell geladen (kein Crash)
- [ ] Tests: `LLMPostProcessorTests` (Mock-Model), `OllamaProcessorTests` (Mock-URLSession), `TextNormalizerTests`

## Offene Fragen

- mlx-swift Version: aktuell `0.21.x` — auf Kompatibilität mit WhisperKit's mlx-Abhängigkeit prüfen (Versionskonflikte via SPM möglich)
- Soll mlx-swift das System-Prompt KV-Caching von Anfang an implementieren oder erst als Optimierung in Phase 7?
- Ollama als primäres Backend beibehalten oder mlx-swift zuerst?
