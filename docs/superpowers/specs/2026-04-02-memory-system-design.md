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


| Field               | Type        | Description                                                                          |
| ------------------- | ----------- | ------------------------------------------------------------------------------------ |
| `id`                | TEXT (UUID) | Primary key                                                                          |
| `type`              | TEXT        | `task_state` | `preference` | `project_context` | `decision` | `pitfall` | `insight` |
| `project`           | TEXT        | Project identifier (e.g. "content-factory")                                          |
| `title`             | TEXT        | Short descriptive title                                                              |
| `content`           | TEXT        | Full memory content                                                                  |
| `embedding`         | BLOB        | bge-m3 vector (1024 floats)                                                          |
| `importance`        | REAL        | Dynamic priority score (0.0–1.0)                                                     |
| `source`            | TEXT        | `auto` | `explicit`                                                                  |
| `tags`              | TEXT        | JSON array of keyword tags                                                           |
| `created_at`        | TEXT        | ISO timestamp                                                                        |
| `updated_at`        | TEXT        | ISO timestamp                                                                        |
| `accessed_at`       | TEXT        | Last retrieval time                                                                  |
| `access_count`      | INTEGER     | Times retrieved                                                                      |
| `status`            | TEXT        | `active` | `archived`                                                                |
| `verified`          | TEXT        | `verified` | `unverified` | `rejected` | `conflict` — trustworthiness status         |
| `scope`             | TEXT        | `project` | `global` — cross-project visibility                                      |
| `accessed_projects` | TEXT        | JSON array of project names that have retrieved this memory                          |


### Session


| Field              | Type        | Description                      |
| ------------------ | ----------- | -------------------------------- |
| `id`               | TEXT (UUID) | Primary key                      |
| `project`          | TEXT        | Project identifier               |
| `summary`          | TEXT        | What was done in this session    |
| `started_at`       | TEXT        | ISO timestamp                    |
| `ended_at`         | TEXT        | ISO timestamp                    |
| `memories_created` | TEXT        | JSON array of memory IDs created |


### Performance Log


| Field          | Type    | Description                         |
| -------------- | ------- | ----------------------------------- |
| `timestamp`    | TEXT    | ISO timestamp                       |
| `operation`    | TEXT    | "recall" | "store"                  |
| `latency_ms`   | REAL    | Actual execution time               |
| `memory_count` | INTEGER | Total memories at time of operation |
| `result_count` | INTEGER | Results returned                    |


---

## Memory Types & Dynamic Importance


| Type                  | Base Importance | Decay Rate       | Lifecycle                                                  |
| --------------------- | --------------- | ---------------- | ---------------------------------------------------------- |
| `preference`          | 0.95            | 0.0 (never)      | Never archive, never delete                                |
| `project_context`     | 0.85            | 0.01 (very slow) | Never archive within project; can be updated/replaced      |
| `task_state` (active) | 0.9             | 0.3 (fast)       | Completed → importance drops to 0.2, archived after 7 days |
| `pitfall`             | 0.7             | 0.02 (slow)      | Never decay; can be merged with similar entries            |
| `decision`            | 0.5             | 0.05 (moderate)  | Access resets decay timer; ~20 days to halve               |


Explicit memories (`source: "explicit"`) get importance +0.1 bonus.

---

## MCP Tools

### Write Tools

`**memory_store`**

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

`**memory_update`**

- Params: `id` (string), `content?` (string), `importance?` (number), `tags?` (string[])
- Re-generates embedding if content changed

`**memory_delete**`

- Params: `id` (string)

### Read Tools

`**memory_recall**`

- Params: `query` (string), `project?` (string), `type?` (enum), `limit?` (number, default 5), `min_similarity?` (number, default 0.3)
- Behavior: query → bge-m3 embedding → cosine similarity search → filter → rank by `final_score` → update accessed_at/access_count
- Returns: `[{ id, title, content, type, similarity, project }]`

`**memory_list**`

- Params: `project?` (string), `type?` (enum), `limit?` (number, default 20), `sort?` ("recent" | "importance" | "accessed")
- Structured browsing without semantic search

### Session Tools

`**session_start**`

- Params: `working_directory` (string), `task_hint?` (string)
- Behavior: Infer project from directory (git repo name > dir name) → load active task_states + all preferences + project_context → if task_hint provided, semantic search for relevant pitfalls/decisions → assemble compressed context within token budget
- Returns: `{ project, active_tasks, preferences, context, relevant, recent_unverified, conflicts, proactive_warnings, token_estimate }`
  - `recent_unverified`: up to 3 recent `unverified` memories for lightweight review
  - `conflicts`: any memories with `verified: "conflict"` awaiting user resolution
  - `proactive_warnings`: insights triggered by task_hint tag matches
- Token budget: 2000 tokens (configurable), allocation: preference (~~200) → task_state (~~400) → project_context (~400) → remaining filled by semantic search results sorted by final_score
- Ranking applies `verified` weight: `verified` ×1.0, `unverified` ×0.7, `rejected` excluded before ranking, `conflict` surfaced separately (not ranked)

`**session_end**`

- Params: `summary` (string), `completed_tasks?` (string[])
- Behavior: Decay completed task_states to importance 0.2 → extract new memories from summary by keyword patterns → store session record → update snapshot

### Maintenance Tools

`**memory_health**`

- Params: none
- Returns: `{ status, ollama, db_integrity, memories, latency_avg_ms, db_size_mb, last_backup, issues, fix_suggestions }`

`**memory_diagnose**`

- Params: `issue?` (string)
- Behavior: Deep self-check → collect recent 50 error logs → collect system environment → generate report → save to `data/diagnostics/`
- Returns: `{ report_path, summary, suggested_fix, can_auto_fix, handoff_prompt }`

`**memory_compact**`

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


| Trigger                               | Memory Type       | Action                               |
| ------------------------------------- | ----------------- | ------------------------------------ |
| Session start                         | —                 | Call `session_start`                 |
| Task/phase completed                  | `task_state`      | Store progress and next steps        |
| Architecture/tech decision made       | `decision`        | Store decision and reasoning         |
| Bug fixed / error solved              | `pitfall`         | Store error symptoms + solution      |
| User says "记住/remember/记得"            | Per content       | Store with `source: "explicit"`      |
| New user preference discovered        | `preference`      | Store preference                     |
| First contact with a project          | `project_context` | Store architecture, stack, structure |
| Session ending / context getting long | —                 | Call `session_end`                   |
| MCP unavailable                       | —                 | Fallback to snapshot file            |


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


| Stage             | Behavior                                                                                                                       |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| **Create**        | Agent auto-extracts or user triggers → embedding → dedup → store (status: active)                                              |
| **Active Use**    | Each recall hit → access_count +1, accessed_at refreshed → recency stays high                                                  |
| **Cool Down**     | Long unaccessed → recency_factor drops by decay_rate → excluded from session_start injection → still findable by memory_recall |
| **Archive/Merge** | Daily compact: importance <0.1 → archived; similarity >0.9 with another → merge; completed task_state >7 days → archived       |
| **Pre-cleanup**   | Archived memories approaching 90 days → trigger notification flow (see Graceful Deletion below)                                |
| **Cleanup**       | Only after user has downloaded/acknowledged → physical delete. **Exception:** `source: "explicit"` memories are NEVER deleted  |


### Graceful Deletion Protocol

Memories are NEVER silently deleted. The following flow ensures the user always has a chance to backup:

```
Day 83: 记忆已归档 83 天
    ↓
Telegram 通知 + alert 文件:
"以下 N 条记忆将在 7 天后被清理，请及时下载备份：
 vega export --archived --before 90d --format json"
    ↓
Day 90: 检查用户是否已下载
    ├── 已下载（vega export 被调用过）→ 执行清理
    └── 未下载 → 延长 3 天缓冲期
        ↓
        每天发 Telegram 提醒:
        "⚠ 还有 N 天缓冲期，请尽快备份即将清理的记忆"
        ↓
Day 93: 再次检查
    ├── 已下载 → 执行清理
    └── 仍未下载 → 再延长 3 天（最多延长 2 次 = 6 天）
        ↓
Day 96: 最终检查
    ├── 已下载 → 执行清理
    └── 仍未下载 → 标记为 "cleanup_blocked"，不清理
        → Telegram: "记忆清理已暂停，等待你手动处理"
        → 直到用户执行 vega export 或 vega cleanup --confirm
```

**"已下载"的判定：** 系统记录 `vega export` 命令的最后执行时间。如果在通知发出后有过 export 操作且覆盖了待清理的记忆范围，则视为已下载。

**CLI 命令：**

```bash
vega export --archived --before 90d --format json -o ~/backups/vega-archive.json
vega cleanup --confirm    # 手动确认清理被阻塞的记忆
```

### Type-Specific Rules


| Type              | Special Rule                                                                       |
| ----------------- | ---------------------------------------------------------------------------------- |
| `preference`      | Never decay, never archive, never delete — only removed by explicit user request   |
| `task_state`      | Completed → importance 0.2 → archived after 7 days (most aggressive recycling)     |
| `pitfall`         | Never decay; can be merged — multiple records of same pitfall consolidate into one |
| `project_context` | Never decay within project; can be **replaced** when architecture changes          |
| `decision`        | Normal decay; single access resets decay timer                                     |


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


| Level        | Frequency       | Checks                                                                                              | Trigger                           |
| ------------ | --------------- | --------------------------------------------------------------------------------------------------- | --------------------------------- |
| **Realtime** | Every tool call | Ollama connectivity, SQLite read/write, per-call latency                                            | Internal, ~1ms overhead           |
| **Daily**    | Every 24h       | Backup memory.db, scan/rebuild missing embeddings, refresh snapshot, run compact, clean old backups | Internal timer + launchd fallback |
| **Weekly**   | Sundays 03:00   | PRAGMA integrity_check, performance trends, growth stats, quality metrics (% unaccessed >30d)       | Same as daily                     |


### Auto-Repair Matrix


| Failure                    | Severity | Auto-Fix | Strategy                                                                                                                                                                                                                                                                                |
| -------------------------- | -------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ollama unresponsive        | Medium   | Yes      | Retry 3× → degrade to FTS5 keyword search (indexed columns: `title`, `content`, `tags`; FTS5 virtual table created at DB init alongside main tables); new memories stored with `embedding = NULL`; background retry every 5 min; when Ollama returns, batch-rebuild all NULL embeddings |
| Missing/corrupt embedding  | Low      | Yes      | Detect at startup + daily check → regenerate via Ollama                                                                                                                                                                                                                                 |
| SQLite corruption          | High     | Partial  | Auto-restore from most recent daily backup                                                                                                                                                                                                                                              |
| Memory quality degradation | Medium   | Yes      | `memory_compact` merges redundant, archives stale entries                                                                                                                                                                                                                               |
| MCP server crash           | Low      | N/A      | MCP is stdio — Cursor re-spawns it on next tool call; no persistent state to lose (all state in SQLite). Scheduler daemon (launchd KeepAlive) handles background tasks independently.                                                                                                   |
| Disk full                  | High     | No       | Alert via Telegram + alert file                                                                                                                                                                                                                                                         |


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


| Channel          | Purpose                     | Mechanism                                                    |
| ---------------- | --------------------------- | ------------------------------------------------------------ |
| **Telegram Bot** | Real-time push notification | HTTP POST to Bot API (dedicated bot, token via env var)      |
| **Alert File**   | In-Cursor notification      | `data/alerts/active-alert.md` — Agent reads at session start |


### Notification Levels


| Level      | Telegram     | Alert File | Triggers                                             |
| ---------- | ------------ | ---------- | ---------------------------------------------------- |
| 🔴 Error   | Immediate    | Write      | DB corruption, backup failure, crash-restart         |
| 🟡 Warning | Daily digest | Write      | Ollama down >1h, latency sustained >300ms, disk >80% |
| 🟢 Info    | Silent       | Silent     | Daily backup success, compaction complete            |
| 📊 Weekly  | Summary      | Silent     | Weekly health report                                 |


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


| Existing File                | Action                                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------------------ |
| `common-fixes.md`            | One-time import as `pitfall` type memories; retain as human-curated reference (read-only by MCP) |
| `content-factory-lessons.md` | One-time import with `project: "content-factory"`                                                |
| `AGENTS.md` memory rules     | Migrate to `.cursor/rules/memory.mdc`; keep non-memory rules in AGENTS.md                        |


---

## Security & Sensitive Information

### Core Rules

1. **Agent can only READ sensitive info** (API keys, tokens, passwords, server IPs) — NEVER modify or delete unless explicitly authorized by the user
2. **Agent is FORBIDDEN from sending sensitive info** to any external service, person, or API unless explicitly authorized by the user
3. **Memory system must not store raw sensitive values** — if a conversation contains `OPENAI_API_KEY=sk-xxxx`, the memory should reference "OpenAI API key is configured" NOT the actual key value

### Encryption at Rest

防止被入侵后记忆泄露：


| Layer           | Method                                        | Purpose            |
| --------------- | --------------------------------------------- | ------------------ |
| **SQLite 加密**   | SQLCipher (AES-256) 或 better-sqlite3 + 自定义加密层 | 整个数据库文件加密，无密钥无法读取  |
| **密钥管理**        | macOS Keychain (`security` CLI) 存储加密密钥        | 密钥不落盘为明文，不在 .env 里 |
| **HTTP API 传输** | Tailscale 已提供 WireGuard 加密隧道                  | 远程访问链路加密           |
| **API 认证**      | API key (auto-generated, hashed stored)       | 远程客户端身份验证          |
| **备份加密**        | 备份文件同样是加密后的 SQLite                            | 备份被拷走也无法读取         |


**入侵场景防护：**

```
攻击者获取了 memory.db 文件
    → SQLCipher 加密，无密钥无法打开
    → 密钥在 macOS Keychain 中，需要系统登录密码

攻击者获取了远程 API 访问
    → 需要 API key（不在文件系统明文存储）
    → Tailscale 网络本身需要设备授权

攻击者获取了 export 备份文件
    → export 输出可选加密: vega export --encrypt --format json
    → 加密的 export 需要密码才能解读
```

### Sensitive Data Filter

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


| Status       | Meaning                           | Retrieval Weight     | How It Gets Set                                         |
| ------------ | --------------------------------- | -------------------- | ------------------------------------------------------- |
| `verified`   | Confirmed accurate                | Normal (×1.0)        | User explicitly stored, or user confirmed during review |
| `unverified` | Auto-extracted, not yet confirmed | Reduced (×0.7)       | Default for all auto-extracted memories                 |
| `rejected`   | User marked as incorrect          | Excluded from search | User says "this is wrong"                               |


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


| Field      | Example                                                         |
| ---------- | --------------------------------------------------------------- |
| type       | `insight`                                                       |
| content    | "FFmpeg 相关任务：8 条踩坑记录中 5 条与文件路径相关（62%）。建议开始 FFmpeg 任务时优先确认路径配置。" |
| tags       | `["ffmpeg", "pattern"]`                                         |
| source     | `auto`                                                          |
| importance | 0.75                                                            |


### Pattern Detection (Rule-Based, No LLM Needed)

Run during weekly health check:


| Pattern                  | Detection Method                             | Insight Example                                                  |
| ------------------------ | -------------------------------------------- | ---------------------------------------------------------------- |
| **Tag clustering**       | Count pitfalls by tag                        | "FFmpeg: 8 pitfalls, 5 about paths (62%)"                        |
| **Repeat offenders**     | Same tag appears in pitfalls across sessions | "中文渲染 issues recur every ~2 weeks"                               |
| **Project risk areas**   | Pitfall density by project module            | "content-factory/pipeline/ has 3× more pitfalls than other dirs" |
| **Decision patterns**    | Cluster decisions by topic                   | "你在数据库选型时 3/4 次选了 SQLite"                                        |
| **Preference stability** | Detect preference changes over time          | "你的注释风格偏好在上月改变过一次"                                               |


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


| Category                     | Examples                               | Detection                                       |
| ---------------------------- | -------------------------------------- | ----------------------------------------------- |
| **Emotional/complaints**     | "这个 API 真垃圾"、"又出 bug 了烦死了"             | Sentiment keywords without actionable content   |
| **Failed debug attempts**    | "试了换端口 3001 没用"                        | Unless the failure itself is the lesson         |
| **One-time queries**         | "这个报错什么意思"、"解释下这段代码"                   | Question without lasting conclusion             |
| **Pasted raw data**          | 200 lines of logs, someone else's code | Large paste blocks without distilled conclusion |
| **Common knowledge**         | "Python for 循环怎么写"                     | Already in documentation / basic knowledge      |
| **One-time commands**        | "跑 npm install"、"重启服务器"                | Imperative commands without reusable context    |
| **Inconclusive exploration** | Browsed files but made no decision     | No resulting action or conclusion               |
| **Meta-discussion**          | Talking about the memory system itself | Self-referential, not project knowledge         |
| **Non-coding tasks**         | "帮我写封邮件"、"查天气"                         | Unrelated to development work                   |


### Implementation

Cursor Rule instructs Agent: "Before calling `memory_store`, verify the content does not fall into any exclusion category. When in doubt, do NOT store."

The MCP server does NOT enforce exclusion — the Agent is responsible for filtering. This keeps the server simple and the rules in one place (Cursor Rule).

---

## Cross-Project Experience Sharing

### Scope Field

Each memory has a `scope` field:


| Scope     | Meaning                 | Retrieval Behavior                               |
| --------- | ----------------------- | ------------------------------------------------ |
| `project` | Relevant to one project | Only returned when searching within that project |
| `global`  | Universally applicable  | Returned for ALL projects                        |


### Auto-Promotion Rules


| Rule                              | Behavior                                  |
| --------------------------------- | ----------------------------------------- |
| `preference` type                 | Always `scope: "global"` at creation      |
| `project_context` type            | Always `scope: "project"` (by definition) |
| Other types                       | Start as `scope: "project"`               |
| Accessed by ≥2 different projects | Auto-promote to `scope: "global"`         |


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

## Multi-Platform Extensibility

Vega 不绑定 Cursor — 通过三层接口服务任何 AI 工具：

```
┌─────────────────────────────────────────────────────┐
│                 Vega Core (library)                  │
├──────────┬──────────┬───────────┬──────────────────┤
│ MCP      │ CLI      │ HTTP API  │ Plugin SDK       │
│ (stdio)  │ (shell)  │ (REST)    │ (future)         │
├──────────┼──────────┼───────────┼──────────────────┤
│ Cursor   │ Claude   │ Remote    │ OpenClaw         │
│          │ Code     │ Cursor    │ lossless-claw    │
│          │ Codex    │ Web UI    │ Custom agents    │
│          │ Scripts  │ (future)  │                  │
└──────────┴──────────┴───────────┴──────────────────┘
```

### 各平台接入方式


| Platform        | Interface             | How to Connect                                                 |
| --------------- | --------------------- | -------------------------------------------------------------- |
| **Cursor**      | MCP (stdio)           | `mcp.json` 注册，Agent 直接调用工具                                     |
| **Claude Code** | CLI                   | 在 CLAUDE.md 里写规则：`遇到问题先跑 vega recall "..." --json`             |
| **Codex CLI**   | CLI                   | 在 AGENTS.md 里写规则，通过 shell 调用 `vega` 命令                         |
| **OpenClaw**    | HTTP API / Plugin SDK | lossless-claw 可配置外部记忆源，或开发 Vega 适配插件                           |
| **其他 MCP 客户端**  | MCP (stdio)           | 任何支持 MCP 的工具都能直接接入                                             |
| **自动化脚本**       | CLI / HTTP API        | `vega recall --json` 或 `curl http://localhost:3271/api/recall` |


### OpenClaw 集成路径

由于用户已有 OpenClaw + lossless-claw 运营经验，预留集成接口：

- Vega HTTP API 兼容 lossless-claw 的 `ingest/assemble` 概念
- 可选：开发一个 OpenClaw 插件适配器，将 Vega 作为 lossless-claw 的外部存储后端
- 两套系统可以共存：OpenClaw 用自己的 lcm.db，Vega 用自己的 memory.db，通过 API 做双向同步

---

## Testing & Benchmarking

### 压力测试


| Test          | Method                        | Target                     |
| ------------- | ----------------------------- | -------------------------- |
| **写入吞吐**      | 批量 store 1000 条记忆，测量总耗时       | < 30s（含 embedding 生成）      |
| **检索延迟**      | 在 1000/5000/10000 条记忆下 recall | < 50ms / < 100ms / < 200ms |
| **并发写入**      | MCP + CLI + HTTP API 同时写入     | SQLite WAL 无死锁，数据一致        |
| **Ollama 压力** | 连续 100 次 embedding 请求         | bge-m3 无 OOM，延迟稳定          |
| **远程同步**      | 客户端离线产生 50 条记忆后重连同步           | < 10s 全部同步完成，无重复           |


### 基准测试


| Metric       | How to Measure                              | Baseline          |
| ------------ | ------------------------------------------- | ----------------- |
| **Token 节省** | 对比 session_start 注入 vs 加载整个 common-fixes.md | 目标：节省 50%+ tokens |
| **记忆精度**     | 手动评估 top-5 recall 结果的相关性 (1-5 分)            | 目标：平均 ≥ 4.0       |
| **查重准确率**    | 故意存入重复内容，检查是否正确合并                           | 目标：95%+ 正确合并      |
| **遗漏率**      | 故意排除不该记的内容，检查是否正确过滤                         | 目标：90%+ 正确排除      |
| **DB 大小效率**  | 每条记忆的平均存储开销                                 | 目标：< 10KB/条       |


### 测试命令

```bash
vega benchmark --suite all        # 运行全部基准测试
vega benchmark --suite write      # 只测写入
vega benchmark --suite recall     # 只测检索
vega benchmark --report           # 生成测试报告
```

---

## Reference Implementations

调研了现有记忆系统的成功案例，以下是对 Vega 设计有借鉴价值的部分：


| System                     | Key Idea Worth Borrowing                          | How Vega Applies It                                        |
| -------------------------- | ------------------------------------------------- | ---------------------------------------------------------- |
| **OpenClaw lossless-claw** | SQLite 作为无损原始存储 + 摘要层 + search/expand 工具按需钻取      | Vega 的 SQLite + embedding + recall 设计直接继承此思路               |
| **LangMem**                | 热路径工具（低延迟 store/search）+ 后台整合任务 分离                | Vega 的 MCP 即时工具 + Scheduler 后台 compact/insight 完全对应        |
| **mem0**                   | 多维度 scope（user / session / agent）+ 只注入 top-k 控制噪音 | Vega 的 project + scope(project/global) + token budget 机制   |
| **Letta (MemGPT)**         | 显式命名记忆块（human/persona）作为一等公民                      | Vega 的 5+1 种记忆类型（task_state 到 insight）是类似思路                |
| **Zep**                    | 时序感知 + 关系图谱                                       | Vega 暂不做图谱，但 accessed_at/created_at 时序权重 + 跨项目自动提升是轻量版时序感知 |


### 与 Vega 的差异化


| 维度     | 其他系统                  | Vega                           |
| ------ | --------------------- | ------------------------------ |
| 部署     | 多数需要云服务或 Postgres     | 纯本地 SQLite + Ollama，零外部依赖      |
| LLM 依赖 | mem0/Letta 核心流程依赖 LLM | 仅 embedding（本地），智能决策交给宿主 Agent |
| 平台     | 各自绑定特定框架              | 三接口（MCP/CLI/HTTP）服务任何 AI 工具    |
| 安全     | 多数不加密                 | SQLCipher 加密 + Keychain 密钥管理   |
| 记忆保护   | 静默删除或手动管理             | 删除前强制通知 + 下载确认 + 缓冲期           |


---

## Phased Delivery Plan

### Phase 1 — Core (本机 Cursor + Claude Code + Codex 跑通)


| Module              | Content                                                                             |
| ------------------- | ----------------------------------------------------------------------------------- |
| Storage engine      | SQLite + WAL + SQLCipher encryption + FTS5                                          |
| Vector layer        | Ollama bge-m3 embedding + brute-force search                                        |
| Hybrid search       | Vector 70% + BM25 30% + RRF fusion                                                  |
| Data model          | 6 memory types + verified status + scope + version history                          |
| MCP Server          | stdio, all tools (store/recall/list/update/delete/session_start/session_end/health) |
| CLI                 | `vega` command, all subcommands                                                     |
| Tiered loading      | L0 title / L1 summary / L2 full content; session_start injects L0+L1 only           |
| Auto-extraction     | Agent auto-write + exclusion rules + sensitive data filter                          |
| Dedup + conflict    | >0.85 merge / contradiction detection / conflict status                             |
| Trust system        | verified / unverified / rejected + lightweight review                               |
| Versioning          | memory_versions table, old version saved on each update                             |
| Lifecycle           | Create → active → cool down → archive + graceful deletion protocol                  |
| Cross-project scope | project / global + auto-promotion                                                   |
| Security            | SQLCipher + macOS Keychain + audit log                                              |
| Backup              | Daily auto-backup + restore                                                         |
| Fallback            | Markdown snapshot + pending queue + recovery import                                 |
| Tool observation    | Cursor Rule guides Agent to capture key tool outputs                                |
| Platform rules      | `.cursor/rules/memory.mdc` + `CLAUDE.md` rules + `AGENTS.md` rules                  |
| Data migration      | Import common-fixes.md + content-factory-lessons.md                                 |
| Health check        | Realtime latency monitoring + memory_health tool                                    |


**Phase 1 acceptance criteria:**

- Mac mini Cursor new session → Agent automatically knows last session state
- Claude Code via `vega recall --json` retrieves memories
- Codex CLI via `vega` commands reads/writes memories
- Three tools working in parallel without conflicts
- session_start token injection < 2000 (vs current common-fixes.md 4000+)

### Phase 2 — Remote + Intelligence + Enhancement


| Module                 | Content                                                                  |
| ---------------------- | ------------------------------------------------------------------------ |
| HTTP API               | Express/Fastify, runs inside scheduler daemon, API key auth              |
| Remote sync            | Client local cache + online forwarding + offline pending + recovery sync |
| One-command setup      | `vega setup --server <ip>`                                               |
| Insights layer         | Rule-based pattern detection + insight type + proactive warnings         |
| Telegram notifications | Error immediate / warning daily / weekly report                          |
| Weekly reports         | Health, performance trends, memory quality analysis                      |
| Diagnostics export     | memory_diagnose + handoff_prompt                                         |
| Stress testing         | `vega benchmark` command, full suite                                     |
| Cloud backup           | Optional export to iCloud / S3                                           |
| CRDT merging           | Multi-agent conflict-free concurrent writes                              |
| OpenClaw integration   | Vega adapter plugin / bidirectional sync                                 |
| sqlite-vec upgrade     | Auto-detect + switch when performance threshold hit                      |


**Phase 2 acceptance criteria:**

- Remote laptop accesses Mac mini memories via Tailscale, offline mode works
- System proactively warns "FFmpeg tasks: watch out for path issues"
- Telegram receives alerts and weekly reports
- `vega benchmark` produces baseline metrics

---

## Codex Collaboration Mechanism

Codex executes implementation; Cursor (this agent) reviews and manages.

### Task Delivery Format

Each Codex task is a markdown file in `docs/superpowers/plans/tasks/`:

```
docs/superpowers/plans/tasks/
├── phase1-01-storage-engine.md
├── phase1-02-embedding-layer.md
├── phase1-03-hybrid-search.md
├── ...
└── phase1-NN-data-migration.md
```

Each task file contains:

- Goal (1 sentence)
- Files to create/modify (exact paths)
- Step-by-step instructions with code
- Test commands with expected output
- Commit message

### Workflow

```
Cursor: 写任务文件 → 放到 tasks/ 目录
    ↓
User: 给 Codex 指定任务文件路径
    ↓
Codex: 读取任务文件 → 执行 → 提交代码
    ↓
Cursor: Review 代码是否符合 spec
    ├── 通过 → 标记任务完成，更新 Notion 看板
    └── 不通过 → 写 review 反馈文件 → Codex 修复
```

### Codex AGENTS.md Rules

在 vega-memory 项目根目录放一份 AGENTS.md，让 Codex 知道项目规范：

```markdown
# Vega Memory System — Codex Rules
- Read the task file FIRST before doing anything
- Follow the spec: docs/superpowers/specs/2026-04-02-memory-system-design.md
- Use TypeScript strict mode
- Use better-sqlite3 for SQLite
- Use @xenova/transformers or direct Ollama HTTP API for embeddings
- Run tests after each task
- Commit after each task with the specified commit message
```

---

## Audit Log

### Schema


| Field       | Type    | Description                                                                           |
| ----------- | ------- | ------------------------------------------------------------------------------------- |
| `id`        | INTEGER | Auto-increment primary key                                                            |
| `timestamp` | TEXT    | ISO timestamp                                                                         |
| `actor`     | TEXT    | `mcp:cursor` | `cli` | `api:<device-name>`                                            |
| `action`    | TEXT    | `store` | `recall` | `update` | `delete` | `export` | `session_start` | `session_end` |
| `memory_id` | TEXT    | Target memory ID (if applicable)                                                      |
| `detail`    | TEXT    | Brief description (query content, operation params)                                   |
| `ip`        | TEXT    | Source IP (for HTTP API access)                                                       |


### CLI Access

```bash
vega audit                          # Recent 50 entries
vega audit --actor "api:*"          # Remote access only
vega audit --action delete          # Delete operations only
vega audit --since 2026-04-01       # By date range
vega audit --memory <id>            # All operations on a specific memory
```

---

## Graceful Export & Backup

### Export Formats


| Format         | Command                                                  | Use Case                        |
| -------------- | -------------------------------------------------------- | ------------------------------- |
| JSON           | `vega export --format json -o backup.json`               | Machine-readable, full metadata |
| Markdown       | `vega export --format md -o backup.md`                   | Human-readable                  |
| Encrypted JSON | `vega export --format json --encrypt -o backup.enc.json` | Secure transfer                 |


### Export Targets

```json
// config.json — optional cloud backup
{
  "backup": {
    "local": {
      "enabled": true,
      "path": "data/backups/"
    },
    "cloud": {
      "enabled": false,
      "provider": "s3 | icloud | gdrive",
      "config": {}
    }
  }
}
```

Cloud backup is **disabled by default**, configurable when needed.

---

## Design Decisions Log


| Decision          | Choice                                          | Reasoning                                                           |
| ----------------- | ----------------------------------------------- | ------------------------------------------------------------------- |
| Project name      | vega-memory / `vega` CLI                        | Named after user's first OpenClaw agent                             |
| Language          | TypeScript                                      | MCP SDK reference implementation; best Cursor ecosystem alignment   |
| Storage           | SQLite                                          | Single-user local system; zero ops overhead                         |
| Embedding         | Ollama bge-m3 (local)                           | Already running via launchd; best multilingual model; zero API cost |
| Search            | Brute-force → sqlite-vec                        | <10K memories = <50ms; auto-upgrade path when needed                |
| LLM intelligence  | Cursor Agent itself                             | Agent decides what to store/search; no additional LLM cost          |
| Write mode        | Fully automatic + explicit trigger              | User shouldn't manage memory; "记住" overrides auto                   |
| Fallback          | Markdown snapshot                               | Natural degradation to existing file-based approach                 |
| Notifications     | Telegram Bot + alert file                       | Real-time push + in-Cursor awareness                                |
| CLI               | Shared core with MCP                            | Any terminal Agent can access memories via shell                    |
| Remote access     | HTTP API + Tailscale + local cache              | Mac mini as primary, remote machines as syncing clients             |
| Memory trust      | verified/unverified/rejected                    | Auto-extracted memories are degraded until confirmed                |
| Cross-project     | Auto-promote scope when accessed by ≥2 projects | No manual classification needed                                     |
| Self-evolution    | Rule-based pattern detection → insight type     | Weekly analysis, no extra LLM cost                                  |
| Security          | Redact sensitive values, read-only agent access | Prevent API keys/tokens from leaking into memory store              |
| Encryption        | SQLCipher + macOS Keychain                      | DB file encrypted at rest; key not stored in plaintext              |
| Graceful deletion | Notify → download → confirm → delete            | Memories never silently lost; user always has backup chance         |
| Multi-platform    | MCP + CLI + HTTP API + Plugin SDK (future)      | Not locked to Cursor; any AI tool can connect                       |
| Benchmarking      | Built-in `vega benchmark` command               | Measurable quality and performance from day one                     |


