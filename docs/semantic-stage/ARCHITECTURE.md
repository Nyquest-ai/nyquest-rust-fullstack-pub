# Nyquest Semantic Compression Stage - Architecture

## Overview

Integration of a local **Qwen 2.5 1.5B-Instruct** model into the Nyquest compression pipeline as a **semantic co-processor**. The model runs on the test server via Ollama, exposed as an OpenAI-compatible endpoint, and is called from the Rust binary via async HTTP when semantic compression is enabled.

### Why Qwen 2.5 1.5B?

- Apache 2.0 license (free for commercial use)
- 1.5B params fits in consumer GPU VRAM (~1.2GB at Q4_K_M)
- 128K context support for large system prompts
- Best-in-class instruction following at 1.5B tier
- Reliable JSON structured output
- ~100-200 tok/s on consumer GPU

## Recommended Hardware

| Spec | Value |
|------|-------|
| CPU | 4+ cores |
| RAM | 8+ GB |
| GPU | NVIDIA GPU (2+ GB VRAM recommended) |
| OS | Ubuntu 22.04+ / Debian 12+ |
| Ollama | Port 11434 (default) |

## Pipeline Position

```
Request In
    |
    v
Stage 1: Provider Detection
Stage 2: Format Translation
Stage 3: Context Optimize (extractive - existing)
Stage 4: OpenClaw Agent Mode
Stage 5: Normalization
    |
    v
*** NEW: Semantic Compress (Qwen 1.5B via Ollama) ***
    |
    v
Stage 6: Rule Compression (350+ regex rules)
Stage 7: Token Accounting
Stage 8: Forward and Return
```

## Three Operational Modes

### Mode 1: History Condensation
Trigger: history > semantic_history_threshold tokens (default 8000)
Neural summarization preserving decisions, errors, URLs, code, constraints.
Replaces extractive summarizer with higher-fidelity neural compression.

### Mode 2: System Prompt Condensation
Trigger: system message > semantic_system_threshold tokens (default 4000)
Rewrites verbose instructions to imperative minimal form.
Preserves all behavioral constraints and tool schemas exactly.

### Mode 3: Redundancy Scoring
Trigger: semantic_dedup enabled
Identifies semantic (not just lexical) duplicates across messages.
Returns scored spans for safe removal.

## Async Pre-computation Strategy

Synchronous inline use would add 2-10s latency. Instead:

1. After Request N completes, if history exceeds threshold, queue background condensation job
2. Result cached in memory keyed by conversation hash
3. Request N+1 checks cache first - HIT = 0ms, MISS = extractive fallback
4. Model has 10-30s between user turns to produce compression

## Config Fields (nyquest.yaml)

```yaml
semantic_enabled: false
semantic_endpoint: "http://localhost:11434/v1/chat/completions"
semantic_model: "qwen2.5:1.5b-instruct"
semantic_timeout_ms: 3000
semantic_history_threshold: 8000
semantic_system_threshold: 4000
semantic_dedup: false
semantic_temperature: 0.0
semantic_max_tokens: 2048
semantic_fallback: "extractive"
```

## Expected Impact

| Metric | Current (Rules Only) | With Semantic Stage |
|--------|---------------------|---------------------|
| Avg token savings | 26.9% | 32-38% |
| System prompt savings | 15-25% | 25-40% |
| History savings (>8K) | 20-30% (extractive) | 40-60% (neural) |
| Added latency (p50) | 0ms | 0ms (async) |
| Cache miss latency | 0ms | 50-100ms (fallback) |
