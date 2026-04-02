# Vega Memory System — Design Spec

## Overview

A local MCP Memory Server with CLI interface and remote access support, designed to prevent memory loss across AI coding sessions, reduce context token consumption, and enable self-evolving experience accumulation through pattern recognition and proactive insights.

**Core problem:** Every new Cursor conversation starts from zero — the Agent doesn't know what was done last time, what the current project state is, or what pitfalls were already solved. The existing `AGENTS.md` + `common-fixes.md` approach relies on loading entire files into context regardless of relevance, wasting tokens and mixing unrelated project experiences.

**Solution:** A TypeScript MCP server (codename: **Vega**) backed by SQLite + Ollama bge-m3 embeddings, providing semantic memory storage, retrieval, lifecycle management, and self-evolving insights. Triple interface: MCP for Cursor, CLI (`vega`) for any terminal-based Agent or script, HTTP API for remote access.

---

## Architecture

```
Mac mini (主机)                          远程电脑 (客户端)
┌────────────────────────────────┐      ┌────────────────────────────┐
│         Core Logic             │      │     Vega Client            │
│         (library)              │      │  ┌───────┐  ┌───────┐     │
│  ┌──────┐ ┌─────┐ ┌────────┐  │      │  │MCP    │  │CLI    │     │
│  │MCP   │ │CLI  │ │HTTP API│◄─┼──────┼──│(stdio)│  │(vega) │     │
│  │(stdio│ │(vega│ │(远程)  │  │ Tail │  └───┬───┘  └───┬───┘     │
│  │)     │ │)    │ │        │  │ scale│      ↓          ↓         │
│  └──┬───┘ └──┬──┘ └───┬────┘  │      │  ┌──────────────────┐     │
│     ↓        ↓       ↓       │      │  │ Local SQLite     │     │
│  ┌─────────────────────────┐  │      │  │ Cache + Sync     │     │
│  │     SQLite (主库)        │  │      │  └──────────────────┘     │
│  │  + Ollama bge-m3        │  │      └────────────────────────────┘
│  └─────────────────────────┘  │
│  ┌─────────────────────────┐  │
│  │  Scheduler Daemon       │  │
│  │  (launchd, always-on)   │  │
│  └─────────────────────────┘  │
└────────────────────────────────┘
```

- **Project name:** vega-memory / CLI command: `vega`
- **Language:** TypeScript
- **Storage:** SQLite (single file, `data/memory.db`)
- **Embedding:** Ollama bge-m3 (local, always-on via launchd, 1024-dim vectors)
- **Search:** Brute-force cosine similarity in memory (auto-upgradeable to sqlite-vec)
- **MCP transport:** stdio (Cursor spawns the process per session)
- **HTTP API:** Express/Fastify server for remote access (runs inside scheduler daemon)
- **Remote access:** Tailscale network, local cache + auto-sync on client machines
- **Background tasks:** Separate lightweight scheduler daemon via macOS launchd, shares the same SQLite DB

---

## Data Model

### Memory Entry

| Field | Type | Description |
|-------|------|-------------|
| `id` | TEXT (UUID) | Primary key |
| `type` | TEXT | `task_state` \| `preference` \| `project_context` \| `decision` \| `pitfall` \| `insight` |
| `project` | TEXT | Project identifier (e.g. "content-factory") |
| `title` | TEXT | Short descriptive title |
| `content` | TEXT | Full memory content |
| `embedding` | BLOB | bge-m3 vector (1024 floats) |
| `importance` | REAL | Dynamic priority score (0.0–1.0) |
| `source` | TEXT | `auto` \| `explicit` |
| `tags` | TEXT | JSON array of keyword tags |
| `created_at` | TEXT | ISO timestamp |
| `updated_at` | TEXT | ISO timestamp |
| `accessed_at` | TEXT | Last retrieval time |
| `access_count` | INTEGER | Times retrieved |
| `status` | TEXT | `active` \| `archived` |
| `verified` | TEXT | `verified` \| `unverified` \| `rejected` \| `conflict` — trustworthiness status |
| `scope` | TEXT | `project` \| `global` — cross-project visibility |
| `accessed_projects` | TEXT | JSON array of project names that have retrieved this memory |

### Session

| Field | Type | Description |
|-------|------|-------------|
| `id` | TEXT (UUID) | Primary key |
| `project` | TEXT | Project identifier |
| `summary` | TEXT | What was done in this session |
| `started_at` | TEXT | ISO timestamp |
| `ended_at` | TEXT | ISO timestamp |
| `memories_created` | TEXT | JSON array of memory IDs created |

### Performance Log

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | TEXT | ISO timestamp |
| `operation` | TEXT | "recall" \| "store" |
| `latency_ms` | REAL | Actual execution time |
| `memory_count` | INTEGER | Total memories at time of operation |
| `result_count` | INTEGER | Results returned |

---

## Memory Types & Dynamic Importance

| Type | Base Importance | Decay Rate | Lifecycle |
|------|----------------|------------|-----------|
| `preference` | 0.95 | 0.0 (never) | Never archive, never delete |
| `project_context` | 0.85 | 0.01 (very slow) | Never archive within project; can be updated/replaced |
| `task_state` (active) | 0.9 | 0.3 (fast) | Completed → importance drops to 0.2, archived after 7 days |
| `pitfall` | 0.7 | 0.02 (slow) | Never decay; can be merged with similar entries |
| `decision` | 0.5 | 0.05 (moderate) | Access resets decay timer; ~20 days to halve |

Explicit memories (`source: "explicit"`) get importance +0.1 bonus.

---

## MCP Tools

### Write Tools

**`memory_store`**
- Params: `content` (string), `type` (enum), `project?` (string), `title?` (string), `tags?` (string[]), `importance?` (number)
- Behavior — ordered pipeline:
  1. **Redact**: Run sensitive data filter, strip secrets
  2. **Embed**: Generate bge-m3 embedding via Ollama
  3. **Similarity search**: Find existing memories in same project + same type with >0.85 similarity
  4. **Branch**:
     - No match (similarity ≤0.85) → **create** new memory (`verified: "unverified"` if auto, `verified: "verified"` if explicit)
     - Match found, content is consistent → **update** existing memory (merge content, refresh timestamps)
     - Match found, content contradicts existing `verified` memory → **create** new memory with `verified: "conflict"`, link to conflicting memory ID in metadata; do NOT overwrite the existing one
  5. **task_state special**: additionally enforce single active entry per logical task per project (replace, not accumulate)
  6. **Auto-tag**: extract keywords from content
  7. **Store**: write to SQLite
- Returns: `{ id, action: "created" | "updated" | "conflict", title }`

**`memory_update`**
- Params: `id` (string), `content?` (string), `importance?` (number), `tags?` (string[])
- Re-generates embedding if content changed

**`memory_delete`**
- Params: `id` (string)

### Read Tools

**`memory_recall`**
- Params: `query` (string), `project?` (string), `type?` (enum), `limit?` (number, default 5), `min_similarity?` (number, default 0.3)
- Behavior: query → bge-m3 embedding → cosine similarity search → filter → rank by `final_score` → update accessed_at/access_count
- Returns: `[{ id, title, content, type, similarity, project }]`

**`memory_list`**
- Params: `project?` (string), `type?` (enum), `limit?` (number, default 20), `sort?` ("recent" | "importance" | "accessed")
- Structured browsing without semantic search

### Session Tools

**`session_start`**
- Params: `working_directory` (string), `task_hint?` (string)
- Behavior: Infer project from directory (git repo name > dir name) → load active task_states + all preferences + project_context → if task_hint provided, semantic search for relevant pitfalls/decisions → assemble compressed context within token budget
- Returns: `{ project, active_tasks, preferences, context, relevant, recent_unverified, conflicts, proactive_warnings, token_estimate }`
  - `recent_unverified`: up to 3 recent `unverified` memories for lightweight review
  - `conflicts`: any memories with `verified: "conflict"` awaiting user resolution
  - `proactive_warnings`: insights triggered by task_hint tag matches
- Token budget: 2000 tokens (configurable), allocation: preference (~200) → task_state (~400) → project_context (~400) → remaining filled by semantic search results sorted by final_score
- Ranking applies `verified` weight: `verified` ×1.0, `unverified` ×0.7, `rejected` excluded before ranking, `conflict` surfaced separately (not ranked)

**`session_end`**
- Params: `summary` (string), `completed_tasks?` (string[])
- Behavior: Decay completed task_states to importance 0.2 → extract new memories from summary by keyword patterns → store session record → update snapshot

### Maintenance Tools

**`memory_health`**
- Params: none
- Returns: `{ status, ollama, db_integrity, memories, latency_avg_ms, db_size_mb, last_backup, issues, fix_suggestions }`

**`memory_diagnose`**
- Params: `issue?` (string)
- Behavior: Deep self-check → collect recent 50 error logs → collect system environment → generate report → save to `data/diagnostics/`
- Returns: `{ report_path, summary, suggested_fix, can_auto_fix, handoff_prompt }`

**`memory_compact`**
- Params: `project?` (string)
- Behavior: Merge memories with >0.9 similarity → archive importance <0.1 entries
- Returns: `{ merged, archived }`

---

## CLI Interface

Global command after `npm link`:

```bash
# Memory operations
vega store "<content>" --type <type> --project <project>
vega recall "<query>" [--project <p>] [--type <t>] [--json|--brief|--verbose]
vega list [--project <p>] [--type <t>] [--sort <s>]
vega update <id> [--importance <n>] [--tags <t>]
vega delete <id>

# Session
vega session-start --dir <path> [--hint "<text>"]
vega session-end --summary "<text>" [--completed <id1,id2>]

# Maintenance
vega health [--json]
vega diagnose [--issue "<description>"]
vega compact [--project <p>]
vega stats

# Import / Export
vega import <file.md>
vega export --format md|json
vega snapshot

# Remote setup (on new machine)
vega setup --server <tailscale-ip>
```

All commands support `--json` for machine-readable output (Agent-friendly).

---

## Retrieval Engine

### Ranking Formula

```
final_score = similarity × 0.5 + importance × 0.3 + recency × 0.2
```

- **similarity**: Cosine similarity between query embedding and memory embedding (0–1)
- **importance**: Memory's dynamic importance value (0–1)
- **recency**: `1 / (1 + days_since_last_access × decay_rate)` — type-specific decay rates as defined above

### Search Engine: Pluggable Interface

```
SearchEngine (interface)
├── BruteForceEngine (default)
│   └── Load all embeddings into memory, compute cosine similarities
│   └── Performance: <50ms for <10,000 memories
└── SqliteVecEngine (upgrade path)
    └── sqlite-vec extension, native vector index
    └── Auto-switch when sqlite-vec is detected
```

**Auto-upgrade behavior:**
- Config: `search_engine: "auto" | "brute_force" | "sqlite_vec"`
- `auto` mode: detect sqlite-vec at startup → use it if available, else brute-force
- Performance monitoring: 10 consecutive recalls >300ms → suggest `npm install sqlite-vec` via recall response
- After install: next restart auto-builds vector index from existing embeddings, zero data migration

---

## Auto-Extraction

### Two-Layer Trigger Design

**Layer 1: Cursor Rules (`.cursor/rules/memory.mdc`)**

Guides the Agent on WHEN to call memory tools:

| Trigger | Memory Type | Action |
|---------|-------------|--------|
| Session start | — | Call `session_start` |
| Task/phase completed | `task_state` | Store progress and next steps |
| Architecture/tech decision made | `decision` | Store decision and reasoning |
| Bug fixed / error solved | `pitfall` | Store error symptoms + solution |
| User says "记住/remember/记得" | Per content | Store with `source: "explicit"` |
| New user preference discovered | `preference` | Store preference |
| First contact with a project | `project_context` | Store architecture, stack, structure |
| Session ending / context getting long | — | Call `session_end` |
| MCP unavailable | — | Fallback to snapshot file |

**Layer 2: MCP Server Internal Logic**

On every `memory_store`:
1. Generate embedding (Ollama bge-m3)
2. Deduplicate: search same project + same type for >0.85 similarity → update instead of create
3. For task_state: enforce single active entry per project per task
4. Auto-extract tags from content
5. Write to SQLite

On `session_end`:
1. Decay completed task_states to 0.2
2. Parse summary for keyword patterns: "决定/选择/因为" → decision, "修复/解决/原因" → pitfall, "偏好/习惯" → preference, "下一步/TODO" → task_state
3. Each candidate goes through the same deduplicate → embed → store pipeline
4. Record session entry

---

## Memory Lifecycle

```
Create → Active Use → Cool Down → Archive/Merge → Cleanup
```

| Stage | Behavior |
|-------|----------|
| **Create** | Agent auto-extracts or user triggers → embedding → dedup → store (status: active) |
| **Active Use** | Each recall hit → access_count +1, accessed_at refreshed → recency stays high |
| **Cool Down** | Long unaccessed → recency_factor drops by decay_rate → excluded from session_start injection → still findable by memory_recall |
| **Archive/Merge** | Daily compact: importance <0.1 → archived; similarity >0.9 with another → merge; completed task_state >7 days → archived |
| **Cleanup** | Monthly: archived >90 days → physical delete. **Exception:** `source: "explicit"` memories are NEVER deleted |

### Type-Specific Rules

| Type | Special Rule |
|------|-------------|
| `preference` | Never decay, never archive, never delete — only removed by explicit user request |
| `task_state` | Completed → importance 0.2 → archived after 7 days (most aggressive recycling) |
| `pitfall` | Never decay; can be merged — multiple records of same pitfall consolidate into one |
| `project_context` | Never decay within project; can be **replaced** when architecture changes |
| `decision` | Normal decay; single access resets decay timer |

### Projected Data Volume

At ~2-3 Cursor sessions/day:
- Daily: ~5-10 new, ~1-2 merged, ~1 archived
- 1 month: ~200 active memories
- 6 months: ~800 active memories
- 1 year: ~1,500 active memories
- DB size: ~5KB/memory → ~7.5MB at 1 year (well within brute-force comfort zone)

---

## Health & Self-Repair

### Three-Level Check Schedule

| Level | Frequency | Checks | Trigger |
|-------|-----------|--------|---------|
| **Realtime** | Every tool call | Ollama connectivity, SQLite read/write, per-call latency | Internal, ~1ms overhead |
| **Daily** | Every 24h | Backup memory.db, scan/rebuild missing embeddings, refresh snapshot, run compact, clean old backups | Internal timer + launchd fallback |
| **Weekly** | Sundays 03:00 | PRAGMA integrity_check, performance trends, growth stats, quality metrics (% unaccessed >30d) | Same as daily |

### Auto-Repair Matrix

| Failure | Severity | Auto-Fix | Strategy |
|---------|----------|----------|----------|
| Ollama unresponsive | Medium | Yes | Retry 3× → degrade to FTS5 keyword search (indexed columns: `title`, `content`, `tags`; FTS5 virtual table created at DB init alongside main tables); new memories stored with `embedding = NULL`; background retry every 5 min; when Ollama returns, batch-rebuild all NULL embeddings |
| Missing/corrupt embedding | Low | Yes | Detect at startup + daily check → regenerate via Ollama |
| SQLite corruption | High | Partial | Auto-restore from most recent daily backup |
| Memory quality degradation | Medium | Yes | `memory_compact` merges redundant, archives stale entries |
| MCP server crash | Low | N/A | MCP is stdio — Cursor re-spawns it on next tool call; no persistent state to lose (all state in SQLite). Scheduler daemon (launchd KeepAlive) handles background tasks independently. |
| Disk full | High | No | Alert via Telegram + alert file |

### Automatic Backup

- Trigger: Server startup, if >24h since last backup
- Location: `data/backups/memory-YYYY-MM-DD.db`
- Retention: 7 most recent, older auto-deleted
- Recovery: `memory_health` detects corruption → auto-restore latest backup

---

## Degradation & Fallback

### Four-Level Degradation Chain

```
Level 0: MCP + Ollama           → Full functionality (semantic search, auto-write)
Level 1: MCP + no Ollama        → FTS5 keyword search, embeddings queued for rebuild
Level 2: MCP + corrupt DB       → Auto-restore from backup, lose <24h of memories
Level 3: MCP completely down    → Markdown snapshot fallback
```

### Snapshot Fallback Mechanism

**During normal operation:** MCP server exports `data/snapshots/memory-snapshot.md` after every `memory_store` or `session_end`. Contains top memories by importance, capped at ~3000 tokens.

**When MCP is unavailable:** Cursor Rule detects MCP tools not responding → instructs Agent to:
1. Read `data/snapshots/memory-snapshot.md` for context
2. Write new memories to `data/snapshots/pending-memories.jsonl`

**On MCP recovery:** Server startup detects `pending-memories.jsonl` → imports each entry through normal embed → dedup → store pipeline → deletes the pending file → regenerates snapshot.

Zero human intervention throughout the entire degrade → fallback → recover cycle.

---

## Notification System

### Dual-Channel Alerts

| Channel | Purpose | Mechanism |
|---------|---------|-----------|
| **Telegram Bot** | Real-time push notification | HTTP POST to Bot API (dedicated bot, token via env var) |
| **Alert File** | In-Cursor notification | `data/alerts/active-alert.md` — Agent reads at session start |

### Notification Levels

| Level | Telegram | Alert File | Triggers |
|-------|----------|------------|----------|
| 🔴 Error | Immediate | Write | DB corruption, backup failure, crash-restart |
| 🟡 Warning | Daily digest | Write | Ollama down >1h, latency sustained >300ms, disk >80% |
| 🟢 Info | Silent | Silent | Daily backup success, compaction complete |
| 📊 Weekly | Summary | Silent | Weekly health report |

### Configuration

```json
{
  "notifications": {
    "telegram": {
      "enabled": true,
      "bot_token": "env:VEGA_TG_BOT_TOKEN",
      "chat_id": "env:VEGA_TG_CHAT_ID"
    },
    "alert_file": {
      "enabled": true,
      "path": "data/alerts/active-alert.md"
    }
  }
}
```

---

## Project Structure

```
vega-memory/
├── package.json
├── tsconfig.json
├── .env                              ← Secrets (gitignored)
├── .env.example
├── src/
│   ├── index.ts                      ← Entry: start MCP server
│   ├── config.ts                     ← Config loader
│   ├── core/                         ← Shared logic (MCP + CLI)
│   │   ├── memory.ts                 ← store / update / delete
│   │   ├── recall.ts                 ← Semantic search + ranking
│   │   ├── session.ts                ← session_start / session_end
│   │   ├── compact.ts               ← Merge & archive
│   │   ├── health.ts                ← Health check & self-repair
│   │   ├── snapshot.ts              ← Markdown snapshot export/import
│   │   └── types.ts                 ← Type definitions
│   ├── db/
│   │   ├── schema.ts                ← Table creation & migrations
│   │   ├── repository.ts            ← CRUD operations
│   │   └── backup.ts                ← Auto-backup & restore
│   ├── embedding/
│   │   └── ollama.ts                ← Ollama bge-m3 integration
│   ├── search/
│   │   ├── engine.ts                ← SearchEngine interface
│   │   ├── brute-force.ts           ← Default implementation
│   │   └── sqlite-vec.ts            ← Upgrade path (placeholder)
│   ├── mcp/
│   │   └── server.ts                ← MCP tool definitions (thin wrapper)
│   ├── cli/
│   │   ├── index.ts                 ← CLI entry (commander.js)
│   │   └── commands/                ← Subcommands
│   │       ├── store.ts
│   │       ├── recall.ts
│   │       ├── session.ts
│   │       ├── health.ts
│   │       ├── import-export.ts
│   │       ├── maintenance.ts
│   │       └── setup.ts             ← Remote machine setup command
│   ├── api/
│   │   ├── server.ts                ← HTTP API server (Express/Fastify)
│   │   ├── auth.ts                  ← API key authentication middleware
│   │   └── routes.ts                ← REST endpoints mirroring MCP tools
│   ├── sync/
│   │   ├── client.ts                ← Remote sync client logic
│   │   └── queue.ts                 ← Pending writes queue for offline mode
│   ├── insights/
│   │   ├── patterns.ts              ← Pattern detection (tag clustering, repeat offenders)
│   │   └── generator.ts             ← Insight memory generation
│   ├── security/
│   │   └── redactor.ts              ← Sensitive data detection & redaction
│   ├── notify/
│   │   ├── telegram.ts              ← Telegram Bot push
│   │   └── alert-file.ts            ← Alert file write
│   └── scheduler/
│       ├── index.ts                 ← Scheduler daemon entry (separate process, includes HTTP API)
│       └── tasks.ts                 ← Daily/weekly task definitions
├── data/                             ← Runtime data (gitignored)
│   ├── memory.db
│   ├── backups/
│   ├── snapshots/
│   │   ├── memory-snapshot.md
│   │   └── pending-memories.jsonl   ← Only exists during MCP downtime
│   ├── reports/
│   ├── diagnostics/
│   ├── alerts/
│   └── logs/
└── tests/
```

---

## Cursor Integration

### MCP Server Registration

```json
// ~/.cursor/mcp.json (Mac mini — server mode)
{
  "mcpServers": {
    "vega": {
      "command": "node",
      "args": ["/Users/johnmacmini/workspace/vega-memory/dist/index.js"],
      "env": {
        "VEGA_DB_PATH": "/Users/johnmacmini/workspace/vega-memory/data/memory.db",
        "OLLAMA_BASE_URL": "http://localhost:11434",
        "VEGA_TG_BOT_TOKEN": "<to be provided>",
        "VEGA_TG_CHAT_ID": "<to be provided>"
      }
    }
  }
}

// Remote machine — client mode (auto-generated by `vega setup`)
{
  "mcpServers": {
    "vega": {
      "command": "node",
      "args": ["vega-memory/dist/index.js"],
      "env": {
        "VEGA_MODE": "client",
        "VEGA_SERVER_URL": "http://100.x.x.x:3271",
        "VEGA_API_KEY": "<auto-generated>",
        "VEGA_CACHE_DB": "~/.vega/cache.db"
      }
    }
  }
}
```

### Cursor Rule

File: `/Users/johnmacmini/workspace/.cursor/rules/memory.mdc`

```
---
globs: ["**/*"]
alwaysApply: true
---

## Memory System Rules

### Normal Mode (MCP available)
- Session start → call vega.session_start(working_directory, task_hint)
- Task completed → call vega.memory_store(type: "task_state")
- Decision made → call vega.memory_store(type: "decision")
- Bug fixed → call vega.memory_store(type: "pitfall")
- New preference discovered → call vega.memory_store(type: "preference")
- User says "记住/remember/记得" → call vega.memory_store(source: "explicit")
- Session ending / context long → call vega.session_end(summary)
- Before storing → verify content does NOT fall into any exclusion category

### Fallback Mode (MCP unavailable)
- Session start → read data/snapshots/memory-snapshot.md
- New memories → append to data/snapshots/pending-memories.jsonl
- Session end → append summary to pending-memories.jsonl

### Alert Check
- Session start → check data/alerts/active-alert.md exists → if yes, read and inform user
```

### Process Architecture

Two separate processes, sharing the same SQLite DB:

**① MCP Server (stdio, Cursor-managed)**
- Cursor spawns this process on demand via `mcp.json` config
- Handles all MCP tool calls (store, recall, session_start, etc.)
- Dies when Cursor session ends — stateless between launches (all state in SQLite)

**② Scheduler Daemon (launchd, always-on)**
- Lightweight background process for tasks that must run without Cursor
- Responsibilities: daily backup, daily compact, weekly health report, weekly insight generation, Telegram alerts
- Hosts the **HTTP API server** on port 3271 for remote client access (see Remote Access section)
- Does NOT serve MCP — MCP is stdio only, handled by process ①

```xml
<!-- ~/Library/LaunchAgents/dev.vega-memory.plist -->
<plist>
  <dict>
    <key>Label</key><string>dev.vega-memory</string>
    <key>ProgramArguments</key><array>
      <string>/usr/local/bin/node</string>
      <string>/Users/johnmacmini/workspace/vega-memory/dist/scheduler.js</string>
    </array>
    <key>KeepAlive</key><true/>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>/Users/johnmacmini/workspace/vega-memory/data/logs/scheduler-stdout.log</string>
    <key>StandardErrorPath</key><string>/Users/johnmacmini/workspace/vega-memory/data/logs/scheduler-stderr.log</string>
  </dict>
</plist>
```

**SQLite concurrency:** Both processes access the same `memory.db`. SQLite WAL mode enables concurrent reads; writes are serialized by SQLite's internal locking — safe for two processes with low write frequency.

---

## Migration Plan

| Existing File | Action |
|---------------|--------|
| `common-fixes.md` | One-time import as `pitfall` type memories; retain as human-curated reference (read-only by MCP) |
| `content-factory-lessons.md` | One-time import with `project: "content-factory"` |
| `AGENTS.md` memory rules | Migrate to `.cursor/rules/memory.mdc`; keep non-memory rules in AGENTS.md |

---

## Security & Sensitive Information

### Core Rules

1. **Agent can only READ sensitive info** (API keys, tokens, passwords, server IPs) — NEVER modify or delete unless explicitly authorized by the user
2. **Agent is FORBIDDEN from sending sensitive info** to any external service, person, or API unless explicitly authorized by the user
3. **Memory system must not store raw sensitive values** — if a conversation contains `OPENAI_API_KEY=sk-xxxx`, the memory should reference "OpenAI API key is configured" NOT the actual key value

### Implementation

- `memory_store` runs a sensitive data filter before storage:
  - Regex patterns for common secrets: API keys, tokens, passwords, private keys, connection strings
  - If detected: strip the sensitive value, store only the contextual reference
  - Log a warning: "Sensitive data detected and redacted from memory"
- The filter is configurable via `config.json` with custom patterns

---

## Remote Access & Multi-Device Sync

### Architecture

Mac mini is the **primary server** (always-on). Remote machines run a **thin client** that connects over Tailscale.

### Mac mini: HTTP API Server

The scheduler daemon is extended to serve an authenticated HTTP API:

- **Endpoint:** `http://<tailscale-ip>:3271`
- **Auth:** API key (generated during setup, stored in client `config.json`)
- **Endpoints mirror MCP tools:** `/api/store`, `/api/recall`, `/api/session/start`, `/api/session/end`, `/api/health`, etc.

### Remote Machine: Vega Client

Operates in `client` mode — all operations forwarded to Mac mini, with local cache for offline resilience.

```
Online:  CLI/MCP → HTTP request to Mac mini → response
Offline: CLI/MCP → local SQLite cache → queue writes to pending
Reconnect: auto-detect Mac mini reachable → sync pending writes → refresh cache
```

### Local Cache Strategy

- Full mirror of memories relevant to the user (synced periodically)
- New memories created offline → stored in `~/.vega/pending/`
- On reconnect: pending memories sent to Mac mini through normal dedup pipeline
- Cache refresh: pull latest memories after sync

### One-Command Setup

```bash
# On any new machine (requires Node.js + Tailscale)
npx vega-memory setup --server <tailscale-ip>

# What it does:
# 1. Installs vega-memory globally
# 2. Connects to Mac mini, generates API key
# 3. Creates ~/.vega/ with config.json + local cache
# 4. Registers MCP server in ~/.cursor/mcp.json (client mode)
# 5. Copies memory.mdc rule to .cursor/rules/
# 6. Syncs initial memory snapshot
# 7. Done — permanent, no re-setup needed
```

Alternative: `curl -fsSL http://<tailscale-ip>:3271/setup | bash`

### Client Config

```json
// ~/.vega/config.json (auto-generated by setup)
{
  "mode": "client",
  "server": "http://100.x.x.x:3271",
  "api_key": "<auto-generated>",
  "cache_db": "~/.vega/cache.db",
  "sync_interval_minutes": 5
}
```

---

## Memory Trustworthiness

### Verification Status

Every memory has a `verified` field:

| Status | Meaning | Retrieval Weight | How It Gets Set |
|--------|---------|-----------------|-----------------|
| `verified` | Confirmed accurate | Normal (×1.0) | User explicitly stored, or user confirmed during review |
| `unverified` | Auto-extracted, not yet confirmed | Reduced (×0.7) | Default for all auto-extracted memories |
| `rejected` | User marked as incorrect | Excluded from search | User says "this is wrong" |

### Lightweight Review Mechanism

During `session_start`, include up to 3 recent `unverified` memories in the response:

```
recent_unverified: [
  { id: "abc", title: "Phase 3 选用 ASS 字幕格式", created_at: "..." },
  { id: "def", title: "用户不喜欢过多注释", created_at: "..." }
]
```

Cursor Rule instructs Agent to briefly mention these:
> "上次我自动记了：① Phase 3 选用 ASS 字幕格式 ② 不喜欢过多注释。有错的告诉我。"

- User says "没问题" → batch update to `verified`
- User says "第一条不对" → mark `rejected` or update content
- No response → stays `unverified`, continues at reduced weight

### Contradiction Detection

When `memory_store` finds an existing memory with >0.85 similarity but significantly different content:
- Do NOT silently overwrite
- Mark the new memory as `conflict` status
- Surface both versions during next `session_start` for user resolution
- Agent presents: "记忆冲突：旧版说 X，新版说 Y。哪个是对的？"

---

## Self-Evolution: Insights Layer

Beyond storing memories, the system identifies patterns and generates proactive insights.

### Insight Generation

A special memory type `insight` (auto-generated, never manually created):

| Field | Example |
|-------|---------|
| type | `insight` |
| content | "FFmpeg 相关任务：8 条踩坑记录中 5 条与文件路径相关（62%）。建议开始 FFmpeg 任务时优先确认路径配置。" |
| tags | `["ffmpeg", "pattern"]` |
| source | `auto` |
| importance | 0.75 |

### Pattern Detection (Rule-Based, No LLM Needed)

Run during weekly health check:

| Pattern | Detection Method | Insight Example |
|---------|-----------------|-----------------|
| **Tag clustering** | Count pitfalls by tag | "FFmpeg: 8 pitfalls, 5 about paths (62%)" |
| **Repeat offenders** | Same tag appears in pitfalls across sessions | "中文渲染 issues recur every ~2 weeks" |
| **Project risk areas** | Pitfall density by project module | "content-factory/pipeline/ has 3× more pitfalls than other dirs" |
| **Decision patterns** | Cluster decisions by topic | "你在数据库选型时 3/4 次选了 SQLite" |
| **Preference stability** | Detect preference changes over time | "你的注释风格偏好在上月改变过一次" |

### Proactive Warning

During `session_start`, if `task_hint` matches tags with known patterns:

```
session_start(task_hint: "修复 FFmpeg 视频合成")
→ 检测到 tag "ffmpeg" 有 insight
→ 返回:
  proactive_warnings: [
    "⚠ FFmpeg 任务历史统计：62% 的问题与文件路径有关，建议优先确认 font/media 路径配置"
  ]
```

---

## Memory Exclusion Rules

The following content types must NOT be stored as memories:

| Category | Examples | Detection |
|----------|----------|-----------|
| **Emotional/complaints** | "这个 API 真垃圾"、"又出 bug 了烦死了" | Sentiment keywords without actionable content |
| **Failed debug attempts** | "试了换端口 3001 没用" | Unless the failure itself is the lesson |
| **One-time queries** | "这个报错什么意思"、"解释下这段代码" | Question without lasting conclusion |
| **Pasted raw data** | 200 lines of logs, someone else's code | Large paste blocks without distilled conclusion |
| **Common knowledge** | "Python for 循环怎么写" | Already in documentation / basic knowledge |
| **One-time commands** | "跑 npm install"、"重启服务器" | Imperative commands without reusable context |
| **Inconclusive exploration** | Browsed files but made no decision | No resulting action or conclusion |
| **Meta-discussion** | Talking about the memory system itself | Self-referential, not project knowledge |
| **Non-coding tasks** | "帮我写封邮件"、"查天气" | Unrelated to development work |

### Implementation

Cursor Rule instructs Agent: "Before calling `memory_store`, verify the content does not fall into any exclusion category. When in doubt, do NOT store."

The MCP server does NOT enforce exclusion — the Agent is responsible for filtering. This keeps the server simple and the rules in one place (Cursor Rule).

---

## Cross-Project Experience Sharing

### Scope Field

Each memory has a `scope` field:

| Scope | Meaning | Retrieval Behavior |
|-------|---------|-------------------|
| `project` | Relevant to one project | Only returned when searching within that project |
| `global` | Universally applicable | Returned for ALL projects |

### Auto-Promotion Rules

| Rule | Behavior |
|------|----------|
| `preference` type | Always `scope: "global"` at creation |
| `project_context` type | Always `scope: "project"` (by definition) |
| Other types | Start as `scope: "project"` |
| Accessed by ≥2 different projects | Auto-promote to `scope: "global"` |

### Tracking

The `accessed_projects` field (JSON array) records which projects have retrieved this memory. When a `memory_recall` hit comes from a different project than the memory's `project` field, that project name is appended to `accessed_projects`. When `len(accessed_projects) >= 2`, scope is promoted to `global`.

### session_start Retrieval Order

```
1. All preference (global, always loaded)
2. Active task_state for current project
3. project_context for current project
4. All scope="global" memories (pitfall, decision, insight)
5. Semantic search with task_hint across all projects (weight ×0.5 for non-current project)
```

---

## Design Decisions Log

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Project name | vega-memory / `vega` CLI | Named after user's first OpenClaw agent |
| Language | TypeScript | MCP SDK reference implementation; best Cursor ecosystem alignment |
| Storage | SQLite | Single-user local system; zero ops overhead |
| Embedding | Ollama bge-m3 (local) | Already running via launchd; best multilingual model; zero API cost |
| Search | Brute-force → sqlite-vec | <10K memories = <50ms; auto-upgrade path when needed |
| LLM intelligence | Cursor Agent itself | Agent decides what to store/search; no additional LLM cost |
| Write mode | Fully automatic + explicit trigger | User shouldn't manage memory; "记住" overrides auto |
| Fallback | Markdown snapshot | Natural degradation to existing file-based approach |
| Notifications | Telegram Bot + alert file | Real-time push + in-Cursor awareness |
| CLI | Shared core with MCP | Any terminal Agent can access memories via shell |
| Remote access | HTTP API + Tailscale + local cache | Mac mini as primary, remote machines as syncing clients |
| Memory trust | verified/unverified/rejected | Auto-extracted memories are degraded until confirmed |
| Cross-project | Auto-promote scope when accessed by ≥2 projects | No manual classification needed |
| Self-evolution | Rule-based pattern detection → insight type | Weekly analysis, no extra LLM cost |
| Security | Redact sensitive values, read-only agent access | Prevent API keys/tokens from leaking into memory store |
