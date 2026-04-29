# Vega Memory System — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working local memory system for AI coding sessions with MCP + CLI interfaces, SQLite storage, Ollama bge-m3 embeddings, and hybrid search.

**Architecture:** TypeScript MCP server (stdio) + CLI (`vega`) sharing a core library. SQLite with WAL + SQLCipher for storage. Ollama bge-m3 for embeddings. Hybrid search (Vector 70% + BM25 30% via FTS5 + RRF fusion). Tiered loading (L0/L1/L2) for token efficiency.

**Tech Stack:** TypeScript, better-sqlite3, @modelcontextprotocol/sdk, commander.js, Ollama HTTP API (localhost:11434)

**Spec:** `docs/superpowers/specs/2026-04-02-memory-system-design.md`

---

### Task 1: Project Scaffold

**Files:**

- Create: `vega-memory/package.json`
- Create: `vega-memory/tsconfig.json`
- Create: `vega-memory/.env.example`
- Create: `vega-memory/.gitignore`
- Create: `vega-memory/src/config.ts`
- Create: `vega-memory/src/core/types.ts`
- **Step 1: Initialize project**

```bash
mkdir -p /Users/johnmacmini/workspace/vega-memory
cd /Users/johnmacmini/workspace/vega-memory
npm init -y
```

- **Step 2: Install dependencies**

```bash
npm install @modelcontextprotocol/sdk better-sqlite3 commander uuid
npm install -D typescript @types/better-sqlite3 @types/node @types/uuid
```

- **Step 3: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "declaration": true,
    "sourceMap": true
  },
  "include": ["src/**/*"]
}
```

- **Step 4: Create .gitignore**

```
node_modules/
dist/
data/
.env
```

- **Step 5: Create .env.example**

```
VEGA_DB_PATH=./data/memory.db
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=bge-m3
VEGA_TG_BOT_TOKEN=
VEGA_TG_CHAT_ID=
```

- **Step 6: Create src/config.ts**

Configuration loader that reads from environment variables with sensible defaults. Include settings for: db path, Ollama URL/model, token budget (default 2000), similarity threshold (default 0.85), backup retention days (default 7), encryption key reference.

- **Step 7: Create src/core/types.ts**

Define all TypeScript types/interfaces:

- `MemoryType`: `'task_state' | 'preference' | 'project_context' | 'decision' | 'pitfall' | 'insight'`
- `MemorySource`: `'auto' | 'explicit'`
- `MemoryStatus`: `'active' | 'archived'`
- `VerifiedStatus`: `'verified' | 'unverified' | 'rejected' | 'conflict'`
- `MemoryScope`: `'project' | 'global'`
- `Memory`: full memory entry interface matching spec data model (all fields including embedding as `Buffer | null`, verified, scope, accessed_projects as `string[]`)
- `MemoryVersion`: `{ id, memory_id, content, embedding, updated_at }`
- `Session`: session entry interface
- `AuditEntry`: audit log entry interface
- `PerformanceLog`: performance log entry interface
- `SessionStartResult`: `{ project, active_tasks, preferences, context, relevant, recent_unverified, conflicts, proactive_warnings, token_estimate }`
- `HealthReport`: health check result interface
- `VegaConfig`: configuration interface
- **Step 8: Update package.json**

Add `"bin": { "vega": "./dist/cli/index.js" }`, `"scripts": { "build": "tsc", "dev": "tsc --watch" }`, set `"type": "module"`.

- **Step 9: Commit**

```bash
git init && git add -A && git commit -m "feat: scaffold vega-memory project with types and config"
```

---

### Task 2: SQLite Database Layer

**Files:**

- Create: `vega-memory/src/db/schema.ts`
- Create: `vega-memory/src/db/repository.ts`
- Create: `vega-memory/src/db/backup.ts`
- Test: `vega-memory/tests/db.test.ts`
- **Step 1: Write tests for database operations**

Test file should cover:

- Database initialization creates all tables
- CRUD operations on memories table
- FTS5 virtual table is created and searchable
- Audit log insertion and querying
- Session table CRUD
- Version history: updating a memory stores old version in memory_versions
- Performance log insertion
- **Step 2: Run tests to verify they fail**

```bash
npx tsx tests/db.test.ts
```

- **Step 3: Create src/db/schema.ts**

SQL schema with tables:

- `memories` — all fields from spec data model including `verified`, `scope`, `accessed_projects`
- `memory_versions` — `id`, `memory_id`, `content`, `embedding`, `importance`, `updated_at`
- `sessions` — session tracking
- `audit_log` — actor, action, memory_id, detail, ip, timestamp
- `performance_log` — timestamp, operation, latency_ms, memory_count, result_count
- `memories_fts` — FTS5 virtual table on `title`, `content`, `tags` columns
- Enable WAL mode: `PRAGMA journal_mode=WAL`
- Run `PRAGMA foreign_keys=ON`

Include a `initializeDatabase(db)` function that creates all tables if not exist, and a `runMigrations(db)` function for future schema changes (version tracked in a `schema_version` table).

- **Step 4: Create src/db/repository.ts**

Repository class wrapping better-sqlite3 with methods:

- `createMemory(memory)` → insert + insert FTS5 row + audit log
- `getMemory(id)` → single memory by ID
- `updateMemory(id, updates)` → save old version to memory_versions first, then update + update FTS5 + audit log
- `deleteMemory(id)` → delete + delete FTS5 + audit log
- `listMemories(filters)` → filtered query with project/type/status/scope
- `searchFTS(query, project?, type?)` → FTS5 BM25 search, return with rank scores
- `getAllEmbeddings(project?, type?)` → return all active memories with non-null embeddings for brute-force search
- `createSession(session)` → insert session
- `logAudit(entry)` → insert audit log
- `logPerformance(entry)` → insert performance log
- `getAuditLog(filters)` → query audit log with actor/action/date filters
- `createVersion(memoryId, oldContent, oldEmbedding)` → insert into memory_versions
- `getVersions(memoryId)` → list version history
- **Step 5: Create src/db/backup.ts**
- `createBackup(dbPath, backupDir)` → copy db file to `backups/memory-YYYY-MM-DD.db`
- `restoreFromBackup(backupDir, dbPath)` → find latest backup, copy back
- `cleanOldBackups(backupDir, retentionDays)` → delete backups older than N days
- `shouldBackup(backupDir)` → check if last backup is >24h old
- **Step 6: Run tests to verify they pass**

```bash
npx tsx tests/db.test.ts
```

- **Step 7: Commit**

```bash
git add -A && git commit -m "feat: SQLite database layer with schema, repository, backup, and FTS5"
```

---

### Task 3: Ollama Embedding Integration

**Files:**

- Create: `vega-memory/src/embedding/ollama.ts`
- Test: `vega-memory/tests/embedding.test.ts`
- **Step 1: Write tests**

Test: generate embedding for a Chinese text string, verify it returns a Float32Array of length 1024. Test: generate embedding for English text. Test: handle Ollama unreachable (should return null, not throw).

- **Step 2: Run tests to verify they fail**
- **Step 3: Create src/embedding/ollama.ts**
- `generateEmbedding(text: string): Promise<Float32Array | null>` — POST to `http://localhost:11434/api/embed` with model `bge-m3`, return embedding vector
- `isOllamaAvailable(): Promise<boolean>` — GET `http://localhost:11434/api/version`
- `cosineSimilarity(a: Float32Array, b: Float32Array): number` — compute cosine similarity
- Handle errors gracefully: timeout (5s), connection refused → return null
- Retry logic: 3 attempts with 1s delay
- **Step 4: Run tests to verify they pass**
- **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Ollama bge-m3 embedding integration with retry and fallback"
```

---

### Task 4: Search Engine (Hybrid Vector + BM25)

**Files:**

- Create: `vega-memory/src/search/engine.ts`
- Create: `vega-memory/src/search/brute-force.ts`
- Create: `vega-memory/src/search/ranking.ts`
- Test: `vega-memory/tests/search.test.ts`
- **Step 1: Write tests**

Test: BruteForceEngine returns top-K results sorted by cosine similarity. Test: BM25 search via FTS5 returns keyword matches with rank. Test: RRF fusion correctly merges vector and BM25 results with 70/30 weighting. Test: final_score formula applies similarity × 0.5 + importance × 0.3 + recency × 0.2. Test: verified weight applied (unverified × 0.7, rejected excluded). Test: results within min_similarity threshold only.

- **Step 2: Run tests to verify they fail**
- **Step 3: Create src/search/engine.ts**

SearchEngine interface:

```typescript
interface SearchEngine {
  search(query: Float32Array, options: SearchOptions): SearchResult[];
}
interface SearchOptions {
  project?: string;
  type?: MemoryType;
  limit: number;
  minSimilarity: number;
}
interface SearchResult {
  memory: Memory;
  similarity: number;
  finalScore: number;
}
```

- **Step 4: Create src/search/brute-force.ts**

BruteForceEngine implementation:

- Load all active embeddings from repository
- Compute cosine similarity against query vector
- Filter by minSimilarity, project, type
- Return sorted by similarity
- **Step 5: Create src/search/ranking.ts**

Ranking functions:

- `computeRecency(accessedAt, decayRate)` → `1 / (1 + daysSince × decayRate)`
- `getDecayRate(type)` → return type-specific decay rate from spec
- `computeFinalScore(similarity, importance, recency, verified)` → apply formula + verified weight
- `hybridSearch(vectorResults, bm25Results)` → RRF fusion: vector weight 0.7, BM25 weight 0.3, reciprocal rank fusion
- `applyVerifiedFilter(results)` → exclude `rejected`, apply ×0.7 to `unverified`
- **Step 6: Run tests to verify they pass**
- **Step 7: Commit**

```bash
git add -A && git commit -m "feat: hybrid search engine with vector + BM25 + RRF fusion and ranking"
```

---

### Task 5: Security Layer (Redaction + Audit)

**Files:**

- Create: `vega-memory/src/security/redactor.ts`
- Test: `vega-memory/tests/security.test.ts`
- **Step 1: Write tests**

Test: detects and redacts API keys (OpenAI, AWS, generic patterns). Test: detects passwords in connection strings. Test: detects private keys. Test: does NOT redact normal text. Test: returns both redacted content and a flag indicating redaction occurred.

- **Step 2: Run tests to verify they fail**
- **Step 3: Create src/security/redactor.ts**
- `redactSensitiveData(content: string): { redacted: string, wasRedacted: boolean }` — scan for sensitive patterns, replace with `[REDACTED:<type>]`
- Patterns: `sk-[a-zA-Z0-9]+`, `AKIA[A-Z0-9]{16}`, `-----BEGIN .* PRIVATE KEY-----`, password in URLs (`://user:pass@`), generic `(api[_-]?key|token|secret|password)\s*[=:]\s*\S+` (case insensitive)
- Configurable: additional patterns from config
- **Step 4: Run tests to verify they pass**
- **Step 5: Commit**

```bash
git add -A && git commit -m "feat: sensitive data redaction with configurable patterns"
```

---

### Task 6: Core Memory Operations (Store / Recall / Lifecycle)

**Files:**

- Create: `vega-memory/src/core/memory.ts`
- Create: `vega-memory/src/core/recall.ts`
- Create: `vega-memory/src/core/compact.ts`
- Create: `vega-memory/src/core/snapshot.ts`
- Test: `vega-memory/tests/core.test.ts`
- **Step 1: Write tests**

Test store: creates memory with embedding, auto-generates title if missing, applies default importance by type, sets verified=unverified for auto source, verified=verified for explicit. Test dedup: storing similar content (>0.85) updates existing instead of creating new. Test conflict: storing content that contradicts verified memory creates conflict entry. Test recall: semantic search returns ranked results with final_score. Test lifecycle: completed task_state importance drops to 0.2. Test compact: merges >0.9 similarity memories, archives importance <0.1. Test scope: preference always global, others start as project.

- **Step 2: Run tests to verify they fail**
- **Step 3: Create src/core/memory.ts**

Memory store pipeline (ordered steps from spec):

1. `redactSensitiveData(content)`
2. `generateEmbedding(content)` via Ollama
3. Similarity search: find existing in same project + same type with >0.85
4. Branch: no match → create new | match + consistent → update | match + contradicts verified → create with `conflict` status
5. For task_state: enforce single active per project per task
6. Auto-extract tags from content (simple keyword extraction)
7. Set default importance by type, +0.1 for explicit source
8. Write to SQLite via repository
9. Log to audit

Also: `updateMemory()`, `deleteMemory()` with version history.

- **Step 4: Create src/core/recall.ts**
- `recallMemories(query, options)` — full pipeline: embed query → brute-force search → FTS5 search → RRF fusion → apply ranking → update accessed_at/access_count/accessed_projects → return top-K
- `listMemories(filters)` — structured listing via repository
- **Step 5: Create src/core/compact.ts**
- `compactMemories(project?)` — find >0.9 similarity pairs → merge → archive importance <0.1 → archive completed task_state >7 days
- `cleanupArchived()` — graceful deletion protocol: check archived >83 days → notify → check >90 days + downloaded → delete. Never delete explicit source.
- **Step 6: Create src/core/snapshot.ts**
- `exportSnapshot(dbPath, outputPath)` — export top memories by importance to markdown file, capped at ~3000 tokens
- `importPending(pendingPath, storeFunction)` — read pending-memories.jsonl, store each via normal pipeline, delete file after
- `generateL0L1(memory)` — generate L0 (title only, ~10 tokens) and L1 (summary, ~50 tokens) from L2 (full content)
- **Step 7: Run tests to verify they pass**
- **Step 8: Commit**

```bash
git add -A && git commit -m "feat: core memory operations — store pipeline, recall, compact, snapshot"
```

---

### Task 7: Session Management

**Files:**

- Create: `vega-memory/src/core/session.ts`
- Test: `vega-memory/tests/session.test.ts`
- **Step 1: Write tests**

Test session_start: infers project from directory, loads preferences + active task_states + project_context, applies token budget, returns structured result. Test session_end: decays completed tasks, extracts memories from summary by keyword patterns, records session. Test: recent_unverified included in session_start. Test: proactive_warnings (if insight memories match task_hint tags).

- **Step 2: Run tests to verify they fail**
- **Step 3: Create src/core/session.ts**
- `sessionStart(workingDirectory, taskHint?)` → infer project (parse git remote or dir name) → load by priority: preferences (all, global) → active task_states (project) → project_context (project) → global scope memories → semantic search with taskHint → collect recent_unverified (up to 3) → collect conflicts → collect proactive_warnings from insight type → assemble within token budget → return SessionStartResult
- `sessionEnd(summary, completedTaskIds?)` → decay completed tasks → parse summary for keyword patterns → store extracted memories → record session → update snapshot
- `inferProject(workingDirectory)` → try `git remote get-url origin` for repo name, fallback to directory name
- **Step 4: Run tests to verify they pass**
- **Step 5: Commit**

```bash
git add -A && git commit -m "feat: session management — start with context injection, end with extraction"
```

---

### Task 8: MCP Server

**Files:**

- Create: `vega-memory/src/index.ts`
- Create: `vega-memory/src/mcp/server.ts`
- Test: manual test via Cursor MCP config
- **Step 1: Create src/mcp/server.ts**

Register all MCP tools using `@modelcontextprotocol/sdk`:

- `memory_store` — params: content, type, project?, title?, tags?, importance? → calls core memory.store()
- `memory_recall` — params: query, project?, type?, limit?, min_similarity? → calls core recall.recallMemories()
- `memory_list` — params: project?, type?, limit?, sort? → calls core recall.listMemories()
- `memory_update` — params: id, content?, importance?, tags? → calls core memory.update()
- `memory_delete` — params: id → calls core memory.delete()
- `session_start` — params: working_directory, task_hint? → calls core session.sessionStart()
- `session_end` — params: summary, completed_tasks? → calls core session.sessionEnd()
- `memory_health` — no params → calls core health.check()
- `memory_compact` — params: project? → calls core compact.compactMemories()

Each tool: validate params → call core → log performance → return result.

- **Step 2: Create src/index.ts**

Entry point: initialize database → create repository → create core services → create MCP server → connect stdio transport.

- **Step 3: Build and test**

```bash
npm run build
echo '{}' | node dist/index.js  # Should start without error
```

- **Step 4: Commit**

```bash
git add -A && git commit -m "feat: MCP server with all tools registered via stdio transport"
```

---

### Task 9: CLI Interface

**Files:**

- Create: `vega-memory/src/cli/index.ts`
- Create: `vega-memory/src/cli/commands/store.ts`
- Create: `vega-memory/src/cli/commands/recall.ts`
- Create: `vega-memory/src/cli/commands/session.ts`
- Create: `vega-memory/src/cli/commands/health.ts`
- Create: `vega-memory/src/cli/commands/import-export.ts`
- Create: `vega-memory/src/cli/commands/maintenance.ts`
- Create: `vega-memory/src/cli/commands/audit.ts`
- **Step 1: Create CLI entry with commander.js**

`src/cli/index.ts` — register all subcommands, add `#!/usr/bin/env node` shebang.

- **Step 2: Implement store command**

`vega store "<content>" --type <type> --project <project> [--tags t1,t2] [--importance 0.8]`

- **Step 3: Implement recall command**

`vega recall "<query>" [--project p] [--type t] [--limit 5] [--json|--brief|--verbose]`

Output formats: `--json` for machine-readable, `--brief` for title+id only, `--verbose` for full content + metadata, default for human-readable summary.

- **Step 4: Implement session commands**

`vega session-start --dir <path> [--hint "text"]`
`vega session-end --summary "text" [--completed id1,id2]`

- **Step 5: Implement health and maintenance**

`vega health [--json]`
`vega compact [--project p]`
`vega stats`

- **Step 6: Implement import/export**

`vega import <file.md>` — parse markdown sections into memory entries
`vega export [--format json|md] [--project p] [--type t] [-o output.json]`
`vega export --archived --before 90d` — for graceful deletion workflow
`vega snapshot` — force refresh markdown snapshot

- **Step 7: Implement audit command**

`vega audit [--actor x] [--action x] [--since date] [--memory id]`

- **Step 8: Build and test**

```bash
npm run build && npm link
vega health
vega store "test memory" --type preference
vega recall "test"
vega list
```

- **Step 9: Commit**

```bash
git add -A && git commit -m "feat: CLI interface with all commands — store, recall, session, health, audit, import/export"
```

---

### Task 10: Platform Rules & Integration

**Files:**

- Create: `/Users/johnmacmini/workspace/.cursor/rules/memory.mdc`
- Create: `vega-memory/rules/CLAUDE.md`
- Create: `vega-memory/rules/AGENTS.md`
- **Step 1: Create Cursor Rule**

`.cursor/rules/memory.mdc` with `alwaysApply: true`:

- Normal mode: session_start on conversation begin, store on task complete / decision / pitfall / preference / user explicit, session_end when done
- Before storing: check exclusion list (9 categories from spec)
- Fallback mode: read snapshot, write to pending JSONL
- Alert check: read active-alert.md at session start
- Lightweight review: mention recent unverified memories
- **Step 2: Create Claude Code rules**

`rules/CLAUDE.md` — rules for Claude Code to use `vega` CLI:

- On session start: run `vega session-start --dir $(pwd) --json`
- Parse JSON output and use as context
- On task complete: run `vega store "..." --type task_state --json`
- On error solved: run `vega store "..." --type pitfall --json`
- On session end: run `vega session-end --summary "..." --json`
- **Step 3: Create Codex rules**

`rules/AGENTS.md` — rules for Codex CLI, same pattern as Claude Code but adapted for Codex conventions.

- **Step 4: Register MCP in Cursor**

Update `~/.cursor/mcp.json` to add vega server config.

- **Step 5: Test end-to-end**

Open new Cursor conversation → verify session_start fires → make a change → verify memory stored → open another conversation → verify previous context loaded.

- **Step 6: Commit**

```bash
git add -A && git commit -m "feat: platform rules for Cursor, Claude Code, and Codex CLI"
```

---

### Task 11: Data Migration

**Files:**

- Create: `vega-memory/src/cli/commands/migrate.ts`
- **Step 1: Implement migration command**

`vega migrate <file>` — smart markdown parser:

- Parse `common-fixes.md`: each `## YYYY-MM-DD Title` section → one or more `pitfall` memories, extract date for created_at
- Parse `content-factory-lessons.md`: same pattern, set `project: "content-factory"`
- For each extracted memory: run through normal store pipeline (embed → dedup → store)
- **Step 2: Run migration**

```bash
vega migrate /Users/johnmacmini/workspace/common-fixes.md
vega migrate /Users/johnmacmini/workspace/content-factory-lessons.md
```

- **Step 3: Verify**

```bash
vega stats
vega list --type pitfall
vega recall "FFmpeg 中文字体"
```

- **Step 4: Commit**

```bash
git add -A && git commit -m "feat: data migration from common-fixes.md and project lessons"
```

---

### Task 12: Scheduler Daemon

**Files:**

- Create: `vega-memory/src/scheduler/index.ts`
- Create: `vega-memory/src/scheduler/tasks.ts`
- **Step 1: Create scheduler daemon**

`src/scheduler/index.ts` — lightweight always-on process:

- Initialize DB connection (shared memory.db)
- Run task scheduler with intervals:
  - Every 24h: backup, compact, rebuild missing embeddings, refresh snapshot, clean old backups
  - Every 7 days (Sunday 03:00): PRAGMA integrity_check, generate weekly report
- Log to `data/logs/scheduler.log`
- **Step 2: Create task definitions**

`src/scheduler/tasks.ts`:

- `dailyMaintenance()` — backup + compact + embedding rebuild + snapshot refresh
- `weeklyHealthReport()` — full integrity check + performance trends + generate report to `data/reports/`
- `checkAlerts()` — check for any conditions that need alerting, write to `data/alerts/active-alert.md`
- **Step 3: Build and test**

```bash
npm run build
node dist/scheduler.js  # Should start and run daily tasks
```

- **Step 4: Create launchd plist**

Create `~/Library/LaunchAgents/dev.vega-memory.plist` with KeepAlive + RunAtLoad.

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.vega-memory.plist
launchctl kickstart -k gui/$(id -u)/dev.vega-memory
```

- **Step 5: Verify**

```bash
launchctl list | grep vega
vega health
```

- **Step 6: Commit**

```bash
git add -A && git commit -m "feat: scheduler daemon with daily backup, compact, and weekly health reports"
```

---

### Task 13: End-to-End Testing & Polish

**Files:**

- Modify: various files for bug fixes
- Create: `vega-memory/tests/e2e.test.ts`
- **Step 1: Write E2E test**

Full workflow test:

1. `session_start` with a test directory
2. `memory_store` — store 5 different memory types
3. `memory_recall` — verify semantic search returns relevant results
4. `memory_store` duplicate — verify dedup merges
5. `memory_update` — verify version history created
6. `session_end` — verify extraction from summary
7. New `session_start` — verify previous memories injected
8. `vega health` — verify healthy status
9. `vega audit` — verify all operations logged
10. Token count verification — session_start injection < 2000 tokens

- **Step 2: Run E2E test**

```bash
npx tsx tests/e2e.test.ts
```

- **Step 3: Fix any issues**
- **Step 4: Test parallel access**

Run simultaneously:

```bash
# Terminal 1: MCP server
echo '{"method":"tools/call","params":{"name":"memory_store","arguments":{"content":"test from mcp","type":"preference"}}}' | node dist/index.js

# Terminal 2: CLI
vega store "test from cli" --type preference
```

Verify both succeed without SQLite locking errors.

- **Step 5: Final verification**

```bash
vega stats
vega health --json
vega list --sort recent
```

- **Step 6: Commit**

```bash
git add -A && git commit -m "test: end-to-end tests and parallel access verification"
```

---

## Phase 1 Complete Checklist

- Mac mini Cursor session → Agent auto-loads previous context via session_start
- Claude Code via `vega recall --json` retrieves memories
- Codex CLI via `vega` commands reads/writes memories
- Three tools in parallel without SQLite conflicts
- session_start token injection < 2000 tokens
- Hybrid search (vector + BM25) returns relevant results for both keyword and semantic queries
- Sensitive data redacted before storage
- Audit log tracks all operations
- Daily backup runs automatically via scheduler
- Markdown snapshot fallback works when MCP unavailable
- common-fixes.md and content-factory-lessons.md migrated successfully

