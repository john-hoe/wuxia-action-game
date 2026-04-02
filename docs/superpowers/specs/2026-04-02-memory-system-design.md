# Vibe Coding Memory System — Design Spec

## Overview

A local MCP Memory Server with CLI interface, designed to prevent memory loss across AI coding sessions, reduce context token consumption, and enable self-evolving experience accumulation.

**Core problem:** Every new Cursor conversation starts from zero — the Agent doesn't know what was done last time, what the current project state is, or what pitfalls were already solved. The existing `AGENTS.md` + `common-fixes.md` approach relies on loading entire files into context regardless of relevance, wasting tokens and mixing unrelated project experiences.

**Solution:** A TypeScript MCP server backed by SQLite + Ollama bge-m3 embeddings, providing semantic memory storage, retrieval, and lifecycle management. Dual interface: MCP for Cursor, CLI for any terminal-based Agent or script.

---

## Architecture

```
                        ┌─────────────────┐
                        │   Core Logic    │
                        │   (library)     │
                        └────────┬────────┘
                          ┌──────┴──────┐
                          ↓             ↓
                   ┌────────────┐  ┌─────────┐
                   │ MCP Server │  │   CLI   │
                   │  (Cursor)  │  │ (终端)   │
                   └──────┬─────┘  └────┬────┘
                          ↓             ↓
                   ┌─────────────────────────┐
                   │       SQLite DB         │
                   │  + Ollama bge-m3        │
                   │  (localhost:11434)       │
                   └─────────────────────────┘
```

- **Language:** TypeScript
- **Storage:** SQLite (single file, `data/memory.db`)
- **Embedding:** Ollama bge-m3 (local, always-on via launchd, 1024-dim vectors)
- **Search:** Brute-force cosine similarity in memory (auto-upgradeable to sqlite-vec)
- **MCP transport:** stdio (Cursor spawns the process per session)
- **Background tasks:** Separate lightweight scheduler daemon via macOS launchd, shares the same SQLite DB

---

## Data Model

### Memory Entry

| Field | Type | Description |
|-------|------|-------------|
| `id` | TEXT (UUID) | Primary key |
| `type` | TEXT | `task_state` \| `preference` \| `project_context` \| `decision` \| `pitfall` |
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
- Behavior: Generate bge-m3 embedding → deduplicate (>0.85 similarity within same project + same type = update existing; this rule applies uniformly to ALL types — two pitfalls about the same issue merge, two decisions about the same topic merge, etc.) → for task_state specifically: additionally enforce single active entry per logical task per project (replace, not accumulate) → auto-extract tags → store in SQLite
- Returns: `{ id, created | updated, title }`

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
- Returns: `{ project, active_tasks, preferences, context, relevant, token_estimate }`
- Token budget: 2000 tokens (configurable), allocation: preference (~200) → task_state (~400) → project_context (~400) → remaining filled by semantic search results sorted by final_score

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
memory store "<content>" --type <type> --project <project>
memory recall "<query>" [--project <p>] [--type <t>] [--json|--brief|--verbose]
memory list [--project <p>] [--type <t>] [--sort <s>]
memory update <id> [--importance <n>] [--tags <t>]
memory delete <id>

# Session
memory session-start --dir <path> [--hint "<text>"]
memory session-end --summary "<text>" [--completed <id1,id2>]

# Maintenance
memory health [--json]
memory diagnose [--issue "<description>"]
memory compact [--project <p>]
memory stats

# Import / Export
memory import <file.md>
memory export --format md|json
memory snapshot
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
      "bot_token": "env:MEMORY_TG_BOT_TOKEN",
      "chat_id": "env:MEMORY_TG_CHAT_ID"
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
cursor-memory-server/
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
│   │       └── maintenance.ts
│   ├── notify/
│   │   ├── telegram.ts              ← Telegram Bot push
│   │   └── alert-file.ts            ← Alert file write
│   └── scheduler/
│       ├── index.ts                 ← Scheduler daemon entry (separate process)
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
// ~/.cursor/mcp.json
{
  "mcpServers": {
    "memory": {
      "command": "node",
      "args": ["/Users/johnmacmini/workspace/cursor-memory-server/dist/index.js"],
      "env": {
        "MEMORY_DB_PATH": "/Users/johnmacmini/workspace/cursor-memory-server/data/memory.db",
        "OLLAMA_BASE_URL": "http://localhost:11434",
        "MEMORY_TG_BOT_TOKEN": "<to be provided>",
        "MEMORY_TG_CHAT_ID": "<to be provided>"
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
- Session start → call memory.session_start(working_directory, task_hint)
- Task completed → call memory.memory_store(type: "task_state")
- Decision made → call memory.memory_store(type: "decision")
- Bug fixed → call memory.memory_store(type: "pitfall")
- New preference discovered → call memory.memory_store(type: "preference")
- User says "记住/remember/记得" → call memory.memory_store(source: "explicit")
- Session ending / context long → call memory.session_end(summary)

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
- Responsibilities: daily backup, daily compact, weekly health report, Telegram alerts
- Does NOT serve MCP — only reads/writes SQLite and sends notifications

```xml
<!-- ~/Library/LaunchAgents/dev.memory-scheduler.plist -->
<plist>
  <dict>
    <key>Label</key><string>dev.memory-scheduler</string>
    <key>ProgramArguments</key><array>
      <string>/usr/local/bin/node</string>
      <string>/Users/johnmacmini/workspace/cursor-memory-server/dist/scheduler.js</string>
    </array>
    <key>KeepAlive</key><true/>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>/Users/johnmacmini/workspace/cursor-memory-server/data/logs/scheduler-stdout.log</string>
    <key>StandardErrorPath</key><string>/Users/johnmacmini/workspace/cursor-memory-server/data/logs/scheduler-stderr.log</string>
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

## Design Decisions Log

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Language | TypeScript | MCP SDK reference implementation; best Cursor ecosystem alignment |
| Storage | SQLite | Single-user local system; zero ops overhead |
| Embedding | Ollama bge-m3 (local) | Already running via launchd; best multilingual model; zero API cost |
| Search | Brute-force → sqlite-vec | <10K memories = <50ms; auto-upgrade path when needed |
| LLM intelligence | Cursor Agent itself | Agent decides what to store/search; no additional LLM cost |
| Write mode | Fully automatic + explicit trigger | User shouldn't manage memory; "记住" overrides auto |
| Fallback | Markdown snapshot | Natural degradation to existing file-based approach |
| Notifications | Telegram Bot + alert file | Real-time push + in-Cursor awareness |
| CLI | Shared core with MCP | Any terminal Agent can access memories via shell |
