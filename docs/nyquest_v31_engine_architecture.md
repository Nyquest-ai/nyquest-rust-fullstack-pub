---
title: "Nyquest v3.1.1 — Compression Engine Architecture"
subtitle: "Full Rust Stack • Technical Reference • March 2026"
author: "Nyquest AI"
date: "2026-03-02"
---

# 1. Executive Overview

Nyquest is a transparent, drop-in proxy that sits between any LLM client and any LLM provider. Every API request passes through a multi-stage semantic compression pipeline that eliminates redundant tokens before they reach the upstream model, reducing cost and latency while preserving meaning.

Version 3.1.1 is a complete Rust rewrite with six major subsystems: a 350+ rule compression engine, an AST-free code minifier, a format optimizer, a prompt-cache reordering engine, per-model compression profiles, and a lock-free rule analytics system. The entire stack — HTTP server, compression engine, CLI installer, provider routing, and metrics — compiles to a single 7 MB binary with zero runtime dependencies.

The system compresses system prompts, user messages, assistant responses (in conversation history), tool results, and embedded code at configurable aggression levels from conservative (level 0.2, filler removal only) to aggressive (level 1.0, full structural rewrite plus code minification and format optimization). Per-model profiles automatically tune compression aggressiveness based on model capability, an OpenClaw mode provides specialized optimization for autonomous agentic systems, and an adaptive auto-scaler dynamically raises compression when context windows fill up.

> **Key Metrics (v3.1.1 Production):** 26.9% avg savings on natural prompts at level 1.0 • 18.4% at level 0.7 • 54–56% on code blocks • 64% on JSON tool results • 76% on large agentic contexts • <2ms compression overhead • 1,408 req/s concurrent throughput • 19/19 live tests passing

# 2. System Architecture

## 2.1 Five-Stage Request Pipeline

Every inbound request follows a deterministic five-stage pipeline. Each stage is optional and independently configurable.

```
Client Request
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 1: Normalize (normalizer.rs)                          │
│ Dedup repeated instructions, resolve conflicts, inject      │
│ speculation boundaries, strip role re-declarations          │
├─────────────────────────────────────────────────────────────┤
│ Stage 2: OpenClaw Agent Mode (openclaw.rs)                  │
│ 7-strategy agentic optimization: tool pruning, schema min,  │
│ thought compression, error dedup, cache injection, sliding  │
│ window, terminal condensation                               │
├─────────────────────────────────────────────────────────────┤
│ Stage 3: Cache Reorder (cache_reorder.rs)                   │
│ Sort tool definitions alphabetically, score system blocks   │
│ by stability, put static content first for prefix caching   │
├─────────────────────────────────────────────────────────────┤
│ Stage 4: Compress (compression/*, profiles.rs)              │
│ Model profile detection → 350+ regex rules across 3 tiers  │
│ → telegraph sentence compression → code minification →      │
│ format optimization → response compression for old turns    │
├─────────────────────────────────────────────────────────────┤
│ Stage 5: Auto-Scale + Forward (server.rs)                   │
│ Dynamic level adjustment based on context fill, provider    │
│ routing, streaming relay, analytics recording, metrics      │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
Upstream Provider (Anthropic, OpenAI, Gemini, xAI, OpenRouter, Local)
```

| Stage | Module | Fires When |
|---|---|---|
| 1. Normalize | normalizer.rs | Level > 0.0 |
| 2. OpenClaw | openclaw.rs | `x-nyquest-openclaw: true` header |
| 3. Cache Reorder | cache_reorder.rs | Always |
| 4. Compress | compression/* + profiles.rs | Level > 0.0 |
| 5. Upstream | server.rs | Always |

## 2.2 Dual API Surface

Nyquest serves six endpoints:

| Endpoint | Method | Description |
|---|---|---|
| `/v1/messages` | POST | Anthropic Messages API (native format) |
| `/v1/chat/completions` | POST | OpenAI-compatible (auto-translates to/from Anthropic) |
| `/health` | GET | Engine version, config, feature flags |
| `/metrics` | GET | Token savings + rule analytics (JSON) |
| `/analytics` | GET | Cumulative rule hit counters (JSON) |
| `/dashboard` | GET | Web dashboard with analytics panel (HTML) |

Both proxy endpoints support streaming (SSE) and non-streaming modes. The OpenAI-compat endpoint auto-detects the target provider from the model name and handles format translation transparently — clients using the OpenAI SDK can target any provider without code changes.

## 2.3 Module Map

| Module | Lines | Responsibility |
|---|---|---|
| compression/rules.rs | 1,057 | 350+ regex compression rules across 18 categories |
| cli/install.rs | 957 | Interactive 11-section setup wizard, headless mode |
| openclaw.rs | 722 | 7-strategy agentic optimization pipeline |
| server.rs | 661 | Axum routes, auto-scaler, streaming relay, analytics |
| compression/engine.rs | 559 | Profile-aware tiered orchestrator, content traversal |
| context.rs | 413 | Request context, provider detection, header extraction |
| stability.rs | 399 | Output stability verification and rollback |
| compression/minify.rs | 341 | AST-free Python/JS/Shell code minifier |
| compression/format.rs | 319 | JSON→YAML/CSV, markdown flattening, schema→TS |
| compression/telegraph.rs | 329 | Sentence-level preamble strip, merge, dedup |
| normalizer.rs | 275 | Dedup, conflict resolution, speculation boundaries |
| security.rs | 262 | AES-256-GCM API key encryption at rest |
| providers/mod.rs | 252 | Provider routing, format transforms, max_tokens floor |
| tokens.rs | 214 | Hybrid token counter (cl100k_base estimation) |
| profiles.rs | 213 | Per-model compression profiles (aggressive/balanced/conservative) |
| dashboard.rs | 205 | Embedded HTML metrics dashboard + analytics panel |
| cli/doctor.rs | 185 | 10-point health check and status command |
| analytics.rs | 184 | Lock-free atomic rule hit counters |
| config.rs | 177 | YAML config with env overrides |
| cli/config_cmd.rs | 157 | show/get/set config subcommands |
| cache_reorder.rs | 129 | Tool/system block sorting for cache hits |
| cli/mod.rs | 72 | Clap CLI definition and command dispatch |
| **TOTAL** | **8,187** | |

## 2.4 Response Headers

Every proxied response includes Nyquest headers for observability:

| Header | Example | Direction |
|---|---|---|
| `x-nyquest-original-tokens` | `358` | Response |
| `x-nyquest-optimized-tokens` | `281` | Response |
| `x-nyquest-savings-percent` | `21.5` | Response |
| `x-nyquest-profile` | `conservative` | Response |
| `x-nyquest-request-id` | `a3c6a68` | Response |
| `x-nyquest-level` | `0.8` | Request (override) |
| `x-nyquest-openclaw` | `true` | Request (enable) |
| `x-nyquest-base-url` | `https://api.x.ai/v1` | Request (routing) |
| `x-nyquest-response-age` | `2` | Request (override) |
| `x-nyquest-bypass` | `true` | Request (passthrough) |

# 3. Compression Engine

## 3.1 Profile-Aware Architecture

The compression engine (`engine.rs`) no longer uses hardcoded level thresholds. Instead, each rule category has its own per-profile activation threshold. The engine receives a `ModelProfile` at construction time and checks `self.level >= profile.category_threshold` for each category independently.

```rust
// Old (hardcoded):
if self.level >= 0.8 {
    result = self.apply_counted(&result, &ADJECTIVE_COLLAPSE, "adjective_collapse");
}

// New (profile-aware):
if self.level >= p.adjective_collapse {  // aggressive=0.8, balanced=0.9, conservative=1.1(disabled)
    result = self.apply_counted(&result, &ADJECTIVE_COLLAPSE, "adjective_collapse");
}
```

This means the same compression level produces different results depending on the model. A request at level 0.8 for Claude Sonnet (aggressive profile) fires all 18 rule categories. The same request at level 0.8 for Claude Haiku (conservative profile) fires only 12 categories — adjective collapse, clause simplify, and adverb strip are held back because small models lose coherence with those rewrites.

## 3.2 Three-Tier Rule Architecture

The 350+ regex rules are organized into three tiers, each building on the previous tier's output. After all regex rules, the telegraph compressor makes sentence-level structural changes, and the code minifier and format optimizer handle structured content.

**Tier 1 — Filler Removal (Level 0.2+).** Strips politeness fillers, verbose connectors, redundant qualifiers, synonym compression, role declarations, scope phrases. ~65 rules. Safe for all models at all levels.

**Tier 2 — Structural Compression (Level 0.5+).** Imperative conversions, clause collapse, developer boilerplate, date compression, credential stripping, semantic formatting, whitespace cleanup. Activates telegraph compressor and inline JSON compaction. ~90 additional rules.

**Tier 3 — Aggressive + Format + Minify (Level 0.8+).** Conversational strip, AI output noise, markdown minification, source code compression, context dedup, disclaimer/adjective/clause/adverb collapse. Plus code block minification (Python/JS/Bash), JSON→YAML/CSV conversion, markdown table flattening. ~60 additional rules + 3 subsystems.

## 3.3 Rule Categories (18)

| Category | Default Tier | Example Transform |
|---|---|---|
| FILLER_PHRASES | 0.2+ | "due to the fact that" → "because" |
| VERBOSE_PHRASES | 0.2+ | "your primary responsibility is to" → removed |
| IMPERATIVE_CONVERSIONS | 0.5+ | "you should always" → "always" |
| CLAUSE_COLLAPSE | 0.5+ | "in situations where" → "when" |
| DEVELOPER_BOILERPLATE | 0.5+ | Strip TODO/FIXME noise |
| SEMANTIC_FORMATTING | 0.5+ | "for example" → "e.g." |
| CREDENTIAL_STRIP | 0.5+ | "with 15 years experience" → removed |
| WHITESPACE_CLEANUP | 0.5+ | Normalize runs, trailing spaces, double newlines |
| CONVERSATIONAL_STRIP | 0.8+ | "this is very important" → removed |
| AI_OUTPUT_NOISE | 0.8+ | "I'd be happy to help" → removed |
| MARKDOWN_MINIFICATION | 0.8+ | Strip emphasis markers, collapse headers |
| SOURCE_CODE_COMPRESSION | 0.8+ | Strip comments in inline code snippets |
| CONTEXT_DEDUPLICATION | 0.8+ | Remove repeated instruction patterns |
| ANTI_NOISE | 0.8+ | Strip meta-instructions and noise markers |
| DISCLAIMER_COLLAPSE | 0.8+ | "saving, investing, budgeting" → "personal finance" |
| ADJECTIVE_COLLAPSE | 0.8+ | Enumeration compression |
| CLAUSE_SIMPLIFY | 0.8+ | "not just X but also Y" → "X and Y" |
| ADVERB_STRIP | 0.8+ | "very important" → "important" |

The "Default Tier" column shows thresholds for the aggressive profile. Conservative and balanced profiles raise specific thresholds — see Section 5 (Model Profiles).

## 3.4 What Is NEVER Modified

Tool/function schemas (names, parameters, types), image blocks, audio blocks, API response bodies, `model`/`max_tokens`/`temperature` parameters, cache control markers, the most recent assistant message in conversation history.

# 4. Code Minifier

The code minifier addresses the single largest untapped source of token waste in agentic conversations: code blocks in tool results. Rather than using tree-sitter (which would add 2–3 MB per language), the minifier uses a state-machine parser that tracks string/comment context to safely strip dead content.

**Implementation:** `compression/minify.rs` (341 lines, zero external dependencies)

**Python:** Docstring removal (triple-quote state tracking), comment stripping (string-aware), pragma preservation (`type:`, `noqa`, `pylint`), blank line collapse. Result: 807→370 tokens (54.2%).

**JavaScript/TypeScript:** Block comment removal (`/* */` including JSDoc), line comment stripping (preserves `///` directives, template-literal-aware), blank line collapse. Result: 1,148→503 tokens (56.2%).

**Shell:** Comment removal (preserves shebangs), blank line collapse. Result: 997→640 tokens (35.8%).

**Language Detection:** Checks code fence markers first (` ```python `, ` ```js `, ` ```bash `). Falls back to heuristic scoring: Python detected when 2+ signals match (`def`+colon, `import`, `class`+colon, `self.`, `__name__`). JavaScript detected when 2+ signals match (`function`/`const`/`let`, arrow functions/`async`, `require`/`import`). Unknown languages pass through unmodified.

# 5. Model Profiles

## 5.1 Profile Architecture

The profiles module (`profiles.rs`, 213 lines) defines three static `ModelProfile` structs, each containing 21 threshold fields — one per rule category plus telegraph intensity. The engine's `compress_text()` method checks `self.level >= profile.{category}` for each rule category independently.

```
Request arrives → model field extracted → detect_profile(model)
                                              │
                                              ▼
                                         ModelProfile
                                              │
                                              ▼
                              CompressionEngine::with_profile(level, profile)
                                              │
                              ┌───────────────┼───────────────┐
                              ▼               ▼               ▼
                      fires category A   skips category B  fires category C
                      (level >= thresh)  (level < thresh)  (level >= thresh)
```

## 5.2 Profile Definitions

| Category | Aggressive | Balanced | Conservative |
|---|---|---|---|
| filler_phrases | 0.2 | 0.2 | 0.2 |
| verbose_phrases | 0.2 | 0.2 | **0.3** |
| imperative_conversions | 0.5 | 0.5 | **0.6** |
| clause_collapse | 0.5 | 0.5 | **0.7** |
| developer_boilerplate | 0.5 | 0.5 | 0.5 |
| semantic_formatting | 0.5 | 0.5 | **0.6** |
| credential_strip | 0.5 | 0.5 | 0.5 |
| whitespace_cleanup | 0.5 | 0.5 | 0.5 |
| conversational_strip | 0.8 | 0.8 | **0.9** |
| ai_output_noise | 0.8 | 0.8 | 0.8 |
| markdown_minification | 0.8 | 0.8 | **0.9** |
| source_code_compression | 0.8 | 0.8 | **0.9** |
| context_deduplication | 0.8 | 0.8 | 0.8 |
| anti_noise | 0.8 | 0.8 | **0.9** |
| disclaimer_collapse | 0.8 | 0.8 | **0.9** |
| adjective_collapse | 0.8 | **0.9** | **1.1** (disabled) |
| clause_simplify | 0.8 | **0.9** | **1.1** (disabled) |
| adverb_strip | 0.8 | **0.9** | **1.1** (disabled) |
| telegraph | 0.5 | **0.6** | **0.8** |
| code_minify | 0.8 | 0.8 | **0.9** |
| format_optimize | 0.8 | 0.8 | **0.9** |
| telegraph_intensity | 1.0 | **0.85** | **0.6** |

Bold values indicate where a profile diverges from aggressive. Setting a threshold above 1.0 effectively disables that category since the maximum compression level is 1.0.

## 5.3 Model Detection

Auto-detection uses substring matching on the `model` field:

| Profile | Models |
|---|---|
| Aggressive | Claude Opus, Claude Sonnet, GPT-4o (not mini), GPT-4 Turbo, Grok 3 (not mini), Gemini Pro, Command R+, Llama 405B/70B, DeepSeek V3, Qwen 72B |
| Conservative | Claude Haiku, GPT-4o Mini, GPT-3.5, Grok 3 Mini, Gemini Flash, Command R Light, Llama 8B/3.2, Mistral 7B, Mixtral 8x7B, Phi, Qwen 7B/14B |
| Balanced | All unrecognized models (safe default) |

The profile name appears in `x-nyquest-profile` response header and server log lines.

## 5.4 Measured Impact

Same 215-token prompt at level 0.8:

| Profile | Output Tokens | Savings |
|---|---|---|
| Aggressive (Sonnet) | 119 | 44.7% |
| Conservative (Haiku) | 132 | 38.6% |
| **Difference** | **13 tokens** | **~6pp** |

# 6. Format Optimizer

**Implementation:** `compression/format.rs` (319 lines)

**JSON → CSV (Arrays).** When all elements in a JSON array are objects with identical keys, converts to CSV with a header row. Eliminates per-object brace/quote overhead. Example: 8-element AP inventory array drops from 466 to 168 tokens (63.9%).

**JSON → YAML (Objects).** Single objects and mixed arrays are converted to compact YAML. Strings only quoted when containing special characters. Example: switch config object drops from 361 to 250 tokens (30.7%).

**Markdown Table Flattening.** Verbose tables with alignment separators and padding are converted to pipe-delimited compact format.

**Tool Schema → TypeScript.** JSON Schema definitions are converted to compact TypeScript-style function signatures for OpenClaw mode.

**Inline JSON Compaction.** At level 0.5+, detects unfenced JSON strings exceeding 150 characters in tool results and applies YAML/CSV conversion.

Safety: conversion only happens if the output is shorter than the input.

# 7. Prompt-Cache Reordering

**Implementation:** `cache_reorder.rs` (129 lines)

Both Anthropic and OpenAI support prefix caching — if the first N tokens match a cached prefix, the provider skips re-processing them. The cache reorder module maximizes hit rates with two strategies:

**Tool Definition Sorting.** Tool definitions in the `tools` array are sorted alphabetically by name, ensuring deterministic ordering even when MCP servers return tools in random order.

**System Block Stability Scoring.** System prompt blocks are scored and sorted highest-first. Scoring: `cache_control` present (+100), role definitions (+30), long blocks (+10/+20), dynamic markers like "today" or "current date" (−20 each). Static boilerplate occupies the first positions; dynamic instructions go last.

# 8. Response Compression

In multi-turn conversations, older assistant responses accumulate significant noise. Nyquest applies a separate, conservative compression pipeline to assistant messages older than the configured age threshold.

The `response_compression_age` config (default: 4) controls how many recent turns are left untouched. Override per-request with `x-nyquest-response-age` header.

The response pipeline uses three progressive tiers:

| Tier | Level | Rules Applied |
|---|---|---|
| Always | All | AI output noise ("Great question!", "Let me know if...", "I hope this helps!") |
| Mid | 0.5+ | Markdown minification, whitespace cleanup, inline JSON compaction |
| Aggressive | 0.8+ | Filler/verbose stripping, conversational strip, code minification, format optimization, telegraph at 70% of configured level |

The telegraph compression in response mode runs at 70% intensity (`level * 0.7`) to avoid over-compressing content the model may reference in later turns.

Response compression tracks its own metrics separately in analytics: tokens saved and responses compressed.

```yaml
# nyquest.yaml
compress_responses: true
response_compression_age: 4
```

# 9. Rule Analytics

**Implementation:** `analytics.rs` (184 lines)

Lock-free `AtomicU64` counters with relaxed memory ordering track every rule category hit across all requests. All 12 tokio worker threads update counters simultaneously with zero contention.

```
Request → compress_request() → CompressionStats (per-request)
                                      │
                                      ▼
                     RuleAnalytics.record_request(stats)  ← atomic fetch_add
                                      │
              ┌───────────────────────┼──────────────────────┐
              ▼                       ▼                      ▼
      GET /analytics           GET /metrics            GET /dashboard
      (full JSON snapshot)    (includes rule_analytics) (visual bar chart)
```

**21 tracked counters:** 19 rule categories + response_compressions + response_tokens_saved.

The dashboard renders a visual bar chart panel with categories sorted by hit count, color-coded by tier (green=0.2+, blue=0.5+, purple=0.8+), showing total requests, total hits, and response compression stats.

Counters are session-scoped (reset on restart). The design avoids persistence to keep the hot path allocation-free.

# 10. Adaptive Auto-Scaler

Rather than requiring operators to set compression levels per request, the auto-scaler dynamically adjusts based on context window utilization. It detects the model's max context from the model name (200K for Anthropic, 128K for GPT-4o, 1M for Gemini, 131K for Grok).

| Context Fill | Behavior | Rationale |
|---|---|---|
| < 100 tokens | Level × 0.5 (min 0.2) | Tiny prompts: maximize fidelity |
| 100–200 tokens | Level × 0.85 | Small prompts: slightly conservative |
| 200 tokens – 50% | Configured level | Normal range: use operator setting |
| 50–80% | Ramp from level → 0.9 | Approaching limit: increase savings |
| 80%+ | Force 1.0 | Critical: maximum compression |

# 11. OpenClaw Agent Mode

Activated by `x-nyquest-openclaw: true`. Provides seven specialized strategies for autonomous agentic systems.

| Strategy | What It Does | Typical Savings |
|---|---|---|
| Tool Result Pruning | Replace old tool outputs with placeholders | 40–76% |
| Schema Minimization | Strip descriptions, convert to TypeScript | 15–25% |
| Thought Compression | Remove `<thinking>` blocks from older turns | 20–40% |
| Error Deduplication | Collapse repeated tracebacks to count | 10–30% |
| Cache Control | Add ephemeral cache_control to system prompt | API cost |
| Terminal Condensation | Strip docstrings/comments from code/logs | 15–30% |
| Sliding Window | Summarize old turns when context exceeds threshold | Variable |

# 12. CLI Installer

The binary is both the server and the management tool. All administration through native Rust subcommands.

| Command | Purpose |
|---|---|
| `nyquest install` | Interactive 11-section wizard: Server, Providers, Compression, Normalization, Context, OpenClaw, Response Compression, Security, Logging, Stability. Writes `nyquest.yaml`, `.env`, optionally installs systemd service. |
| `nyquest install --defaults` | Headless mode for CI/Docker. Combine with `--set key=value`. |
| `nyquest configure` | Re-configure with existing values pre-loaded. `--section providers` to jump. |
| `nyquest doctor` | 10-point health check: engine, config, port, API keys, dashboard, logs, systemd. |
| `nyquest status` | Quick status: config, compression level, OpenClaw, service state. |
| `nyquest config show\|get\|set` | Direct key-value management. Dot-notation: `providers.anthropic.api_key`. |
| `nyquest serve` | Start the proxy (default when no subcommand given). |

CLI dependencies: clap 4 (derive), dialoguer 0.11, console 0.15, dirs 6.

# 13. Security

**AES-256-GCM encryption** for API keys at rest with PBKDF2-SHA256 (600K iterations) key derivation. Memory-only decryption — keys exist in cleartext only in process memory. Localhost binding by default. Zero credential logging — API keys never written to metrics or log files.

**Systemd hardening:** `NoNewPrivileges=true`, `ProtectSystem=strict`, `PrivateTmp=true`.

# 14. Performance Benchmarks

## 14.1 Natural Prompt Compression (8 Scenarios, Level 1.0)

| Scenario | Original | Optimized | Savings |
|---|---|---|---|
| Customer Support | 312 tok | 200 tok | 35.9% |
| Legal Review | — | — | 30.0% |
| Data Science | — | — | 22.0% |
| Travel Planner | — | — | 26.3% |
| Code Review | — | — | 36.6% |
| Financial Advisor | — | — | 17.5% |
| HR Policy | — | — | 26.0% |
| Medical Education | — | — | 16.6% |
| **Aggregate** | **2,201 tok** | **1,609 tok** | **26.9%** |

## 14.2 Code Block Compression (Level 1.0)

| Content | Savings |
|---|---|
| Python (70 lines) | 54.2% |
| JavaScript (95 lines) | 56.2% |
| Bash (95 lines) | 35.8% |

## 14.3 JSON/Data Format Compression (Level 1.0)

| Content | Savings |
|---|---|
| JSON array (8 AP objects) | 63.9% |
| JSON nested (switch config) | 30.7% |

## 14.4 OpenClaw Agent Mode

| Scenario | Savings |
|---|---|
| Multi-turn agent (8 messages) | 4.9% |
| Large result pruning (400-line output) | 76.1% |

## 14.5 Throughput

| Metric | Result |
|---|---|
| Single-thread /health | 156 req/s (6.39ms avg incl. curl overhead) |
| Latency p50 / p90 / p99 | 0.24ms / 0.28ms / 0.39ms |
| Concurrent (20 workers × 10 req) | 1,408 req/s |
| Memory (idle) | 79 MB RSS |
| Threads | 13 (12 tokio workers + main) |

## 14.6 Live Test Suite (19/19 Pass)

| Category | Tests |
|---|---|
| Infrastructure | /health, /dashboard, /metrics |
| Anthropic /v1/messages | Non-streaming, streaming, multi-turn, passthrough (level=0), max compression (level=1) |
| OpenAI /v1/chat/completions | xAI Grok ×3 (non-stream, stream, max_tokens floor), Gemini ×3 |
| OpenClaw Agent Mode | tool_result compression, code+traceback multi-turn, xAI via OpenAI-compat |
| Error Handling | Invalid API key → 401, invalid model → 404 |

# 15. Deployment

Single ~7 MB binary. Deployed as systemd user service on Ubuntu 24.04.

| Component | Path |
|---|---|
| Binary | `~/nyquest/target/release/nyquest` |
| Config | `~/nyquest/nyquest.yaml` |
| Environment | `~/nyquest/.env` |
| Metrics log | `~/nyquest/logs/nyquest_metrics.jsonl` |
| Service | `~/.config/systemd/user/nyquest.service` |
| Port | 5400 (all interfaces) |

# 16. Architecture Roadmap

**Completed:**
- ~~Native Rust CLI installer~~ — 11-section wizard, headless mode, doctor, config management
- ~~Per-model rule profiles~~ — 3 profiles, auto-detected, per-category thresholds, `x-nyquest-profile` header
- ~~Compression analytics dashboard~~ — lock-free atomic counters, `/analytics` endpoint, dashboard panel
- ~~Response compression~~ — progressive 3-tier pipeline, age-based cutoff, per-request override

**Planned:**
- **Semantic deduplication via embeddings.** Replace regex dedup with embedding similarity for cross-sentence redundancy.
- **Local model summarization for OpenClaw.** 10-token semantic summaries from a cheap local model instead of placeholders.
- **Tree-sitter integration (optional).** AST-based code minification for 10+ languages.
- **Windows cross-compilation.** ~30 lines of `#[cfg]` gating on `security.rs` and CLI installer.
- **Persistent analytics with daily rollups.** JSONL or SQLite for cross-session trend tracking.
- **Prometheus/OpenTelemetry export.** Native `/metrics/prometheus` endpoint for Grafana.

---

*Nyquest v3.1.1 — Full Rust Stack — 8,187 lines of Rust — March 2026 — Nyquest AI*
