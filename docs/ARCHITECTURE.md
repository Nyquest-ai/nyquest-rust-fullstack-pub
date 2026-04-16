# Nyquest v3.1 — System Architecture

*Last updated: 2026-03-01*

## Overview

Nyquest is a semantic compression proxy for LLM APIs. It sits between any LLM client and upstream providers, applying a six-stage optimization pipeline that reduces input tokens by 15–76% without degrading output quality or schema integrity.

**v3.1 is a full Rust rewrite.** The Python codebase has been retired. The entire compression engine, HTTP server, provider routing, and all optimization subsystems now run as a single native binary built with Rust + Axum. This eliminates the Python runtime dependency and reduces the deployment footprint to a 13 MB binary with sub-millisecond compression overhead.

**Runtime:** Rust (Tokio + Axum) / Linux x86_64
**Binary:** `nyquest` (~7 MB)
**License:** MIT / Apache-2.0

---

## High-Level Architecture

```
                        ┌──────────────────────────────────────────────┐
                        │         Nyquest Proxy (Axum / Tokio)         │
                        │                127.0.0.1:5400                  │
                        │                                              │
  Client Request ──────▶│  ┌─────────────┐                             │
  (Anthropic or         │  │  Endpoint    │  POST /v1/messages         │
   OpenAI format)       │  │  Router      │  POST /v1/chat/completions │
                        │  └──────┬──────┘  GET  /health,/metrics,...  │
                        │         │                                    │
                        │         ▼                                    │
                        │  ┌─────────────┐                             │
                        │  │  Provider    │  Auto-detect from model    │
                        │  │  Detection   │  name or header override   │
                        │  └──────┬──────┘                             │
                        │         │                                    │
                        │         ▼                                    │
                        │  ┌─────────────┐                             │
                        │  │  Format      │  OpenAI ↔ Anthropic        │
                        │  │  Translation │  bidirectional conversion  │
                        │  └──────┬──────┘                             │
                        │         │                                    │
                        │         ▼                                    │
                        │  ┌──────────────────────────────────────┐    │
                        │  │     Six-Stage Optimization Pipeline  │    │
                        │  │                                      │    │
                        │  │  1. Normalizer (dedup, conflicts)    │    │
                        │  │  2. OpenClaw (agentic optimization)  │    │
                        │  │  3. Cache Reorder (prefix caching)   │    │
                        │  │  4. Compress (350+ rules + minify    │    │
                        │  │     + format optimizer + telegraph)  │    │
                        │  │  5. Semantic LLM (Qwen 2.5 via Ollama)│    │
                        │  │  6. Auto-scale + Forward to provider │    │
                        │  └──────────────────────────────────────┘    │
                        │                                              │
                        │         ▼                                    │
                        │  ┌─────────────┐                             │
                        │  │  Provider    │  Anthropic, OpenAI,        │
                        │  │  Forward     │  Gemini, xAI, OpenRouter,  │
                        │  └──────┬──────┘  Local models               │
                        │         │                                    │
                        └─────────┼────────────────────────────────────┘
                                  │
                        ◀─────────┘  Response (streaming or batch)
```

## Six-Stage Request Pipeline

| Stage | Module | Purpose | Fires When |
|---|---|---|---|
| 1. Normalize | normalizer.rs | Hallucination mitigation, dedup, conflict resolution | Always (non-zero level) |
| 2. OpenClaw | openclaw.rs | Agentic context optimization (7 strategies) | x-nyquest-openclaw: true |
| 3. Cache Reorder | cache_reorder.rs | Sort tools/system for provider prefix caching | Always (NEW in v3.1) |
| 4. Compress | compression/* | Token reduction via 350+ rules + telegraph + minify + format | Level > 0.0 |
| 5. Semantic | semantic.rs | Local LLM condensation (system 56%, history 75%) | semantic_enabled: true |
| 6. Upstream | server.rs | Auto-scale level, forward to provider, log metrics | Always |

## Module Map (v3.1)

| Module | Lines | Responsibility |
|---|---|---|
| server.rs | 620 | Axum routes, auto-scaler, streaming relay, metrics |
| compression/rules.rs | 1,016 | 350+ regex compression rules across 18 categories |
| compression/minify.rs | 341 | AST-free Python/JS/Shell code minifier (NEW in v3.1) |
| compression/format.rs | 319 | JSON→YAML/CSV, markdown flattening, schema→TS (NEW in v3.1) |
| compression/telegraph.rs | 329 | Sentence-level preamble strip, merge, dedup |
| compression/engine.rs | 251 | Tiered orchestrator, content block traversal |
| openclaw.rs | 722 | 7-strategy agentic optimization pipeline |
| cache_reorder.rs | 129 | Tool/system block sorting for cache hits (NEW in v3.1) |
| normalizer.rs | 275 | Dedup, conflict resolution, speculation boundaries |
| context.rs | 413 | Request context, provider detection, header extraction |
| stability.rs | 399 | Output stability verification and rollback |
| tokens.rs | 207 | Hybrid token counter (cl100k_base estimation) |
| security.rs | 262 | AES-256-GCM API key encryption at rest |
| config.rs | 171 | YAML config with hot-reload and env overrides |
| dashboard.rs | 152 | Embedded HTML metrics dashboard |
| providers/mod.rs | 252 | Provider transforms (thinking-model max_tokens floor) |
| **TOTAL** | **6,402** | |

## Three-Tier Rule Architecture

350+ regex rules in three tiers, each building on the previous:

**Tier 1 — Level 0.2+: Filler Removal** (~65 rules)
Strips politeness fillers, verbose connectors, redundant qualifiers, synonym compression, role declarations, scope phrases. Safe for all use cases.

**Tier 2 — Level 0.5+: Structural Compression** (~90 rules)
Imperative conversions, clause collapse, developer boilerplate, date compression, credential stripping. Activates telegraph compressor and inline JSON compaction.

**Tier 3 — Level 0.8+: Aggressive + Format + Minify** (~60 rules + 3 subsystems)
Conversational strip, AI output noise, markdown minification, source code compression, plus code block minification (Python/JS/Bash), JSON→YAML/CSV conversion, markdown table flattening.

## Auto-Scaler

The auto-scaler dynamically adjusts compression level before forwarding:

- Small prompts (<100 tokens): reduced compression for fidelity
- Prompts >50% of context window: progressively ramp toward 1.0
- Prompts >80% of context: maximum compression engages automatically

## Dual API Surface

- `/v1/messages` — Anthropic Messages API (native format)
- `/v1/chat/completions` — OpenAI-compatible (auto-translates to/from Anthropic)

Both endpoints support streaming (SSE) and non-streaming modes. Provider routing via `x-nyquest-base-url` header.

## Deployment

Production deployment on Ubuntu 24.04 via systemd:

```ini
[Unit]
Description=Nyquest Semantic Compression Proxy v3.1.1 (Full Rust Stack)
After=network.target

[Service]
Type=simple
User=<your-user>
WorkingDirectory=~/nyquest
EnvironmentFile=~/nyquest/.env
ExecStart=~/nyquest/nyquest-rust-fullstack
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Optionally exposed via reverse proxy or Cloudflare Tunnel for external access.

## Performance (v3.1.1 Production Benchmarks)

| Metric | Result |
|---|---|
| Health endpoint throughput | 549 req/s (single-thread) |
| Concurrent throughput (20 workers) | 980 req/s |
| Health p50 latency | 1.82ms |
| Proxy overhead vs direct | Negative (faster than direct) |
| RSS memory | 71.4 MB |
| System memory usage | 0.0% |
| Natural system prompt savings (avg) | 18.4% @ 0.7, 26.9% @ 1.0 |
| Max single-scenario savings | 37.2% |
| SSE streaming TTFB | 349ms |

---

For the complete v3.1 engine architecture reference, see [nyquest_v31_engine_architecture.md](nyquest_v31_engine_architecture.md).
