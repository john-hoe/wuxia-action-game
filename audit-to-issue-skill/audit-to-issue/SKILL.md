---
name: audit-to-issue
description: Run a full-repo audit or large-scope review that must continue until the requested scope is fully covered and all confirmed findings are consolidated into one GitHub issue. Use when the user asks for a complete audit, repo-wide review, sustained backlog building, or explicitly says not to stop at intermediate milestones such as issue creation, module-level completion, or one batch of findings.
---

# Audit To Issue

Run large-scope audits without prematurely stopping at convenient milestones.

Use this skill when the task is not "find some problems" but "keep auditing until the requested scope is actually covered and the repair backlog is fully consolidated."

## Core Rule

Do not treat any of the following as completion:

- Creating a GitHub issue
- Updating an issue comment
- Finishing one module
- Finding one batch of issues
- Producing one review report

The task is complete only when the requested scope has been audited end-to-end and confirmed findings have been consolidated into the same repair backlog.

## Workflow

1. Define the true finish line before doing work.
   Capture:
   - Target repo or scope
   - Expected output location
   - Whether findings should be appended to an existing issue or a new issue
   - What counts as "fully covered"

2. Build a coverage map.
   Split the repo into concrete audit lanes such as:
   - Core runtime
   - API / MCP / CLI
   - Auth / tenant / security
   - Wiki / publishing
   - Sync / ingestion / queue
   - Monitoring / scheduler / deploy / docs

3. Audit all lanes, not just the interesting ones.
   Prefer evidence over suspicion.
   Re-check fixes that may have introduced follow-on issues.
   De-duplicate repeated findings before writing them up.

4. Consolidate findings into one issue.
   Prefer appending to the same GitHub issue instead of fragmenting the backlog.
   When adding a finding, include:
   - Severity
   - File or subsystem
   - Why it is a real bug, risk, or completion gap
   - Expected repair direction

5. Keep going after each milestone.
   After creating or updating the issue, return to the remaining unreviewed scope immediately.
   Do not summarize the overall task as "done" while unchecked lanes still exist.

6. Mark completion only after the repo coverage map is exhausted.
   Before stopping, explicitly confirm:
   - No material lanes remain unreviewed
   - Confirmed findings have been appended to the same backlog
   - Repeated or superseded findings have been reconciled

## Progress Discipline

During long audits, keep progress tracking internal and concrete:

- Track completed lanes
- Track remaining lanes
- Track the current percentage as coverage, not confidence

Do not let "good enough" replace the actual stop condition.

## Forced Pause Protocol

If a pause is unavoidable because of context limits, tool failures, or external blockers, leave a resume packet that includes:

- Completion percentage
- Completed scope
- Remaining scope
- The exact next module or file to continue from
- Any already-filed issue URL and the last comment/update point

Do not stop without leaving this packet.

## Parallelization

When useful, use bounded parallel sub-agents for independent audit slices.
Keep write scope empty unless the task explicitly includes fixes.
Use the main thread to integrate, de-duplicate, and maintain the single backlog.

## Output Contract

For the final closeout:

- Give one concise summary
- Point to the canonical GitHub issue
- State coverage percentage or completion
- List any intentionally unreviewed or blocked areas, if any remain

If the task is incomplete, do not present the audit as complete.
