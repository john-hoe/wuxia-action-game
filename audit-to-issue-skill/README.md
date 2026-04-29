# Audit to Issue Skill

Keep long-running repository audits going until the requested scope is actually finished.

This project packages a small but opinionated execution skill for AI coding agents that tend to stop too early after:

- creating a GitHub issue
- updating one issue comment
- finishing one module
- finding one batch of problems

It is especially useful for **Codex**, **ChatGPT-like coding agents**, and similar systems that are strong at local reasoning but can still prematurely treat an intermediate milestone as the end of the task.

## What This Does

The skill enforces one simple rule:

> For repo-wide audit/review tasks, `issue created` is not `task completed`.

It teaches the agent to:

- define a real finish line before starting
- build a repo coverage map
- keep auditing after each issue/comment update
- consolidate findings into one canonical GitHub issue
- leave a structured resume packet if a pause is unavoidable

## Why This Exists

In practice, many AI agents are good at:

- spotting issues quickly
- opening a repair backlog
- producing a clean milestone summary

But they often still stop at the first convincing checkpoint.

That is a bad default for tasks like:

- full-repo security audit
- architecture review
- migration readiness review
- “read the whole codebase and build one repair backlog”

This skill is meant to reduce that failure mode.

## Repository Layout

```text
audit-to-issue-skill/
├── README.md
└── audit-to-issue/
    ├── SKILL.md
    └── agents/
        └── openai.yaml
```

## Install for Codex

Copy the `audit-to-issue` folder into your local Codex skills directory:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
cp -R audit-to-issue "${CODEX_HOME:-$HOME/.codex}/skills/"
```

After that, you can trigger it with:

```text
$audit-to-issue
```

Or by explicitly asking for:

- a full-repo audit
- an audit that must continue until the whole repo is covered
- a single GitHub issue that accumulates all confirmed findings

## Use with ChatGPT

ChatGPT does not natively load Codex local skills, so the best approach is to reuse the same protocol as:

- Custom Instructions
- Project Instructions
- a pinned reusable prompt

Use this contract:

```text
Treat this as a sustained audit task.
Do not treat issue creation, issue comment updates, finishing one module, or finding one batch of issues as completion.
Only stop when the requested scope has been reviewed end-to-end and all confirmed findings have been consolidated into the same GitHub issue.
If you must pause, leave a resume packet with:
- completion percentage
- completed scope
- remaining scope
- exact next file or module to continue from
```

## Best Use Cases

- Full-repo audit
- Security review across the whole repository
- Multi-module refactor review
- Pre-release hardening review
- “Read everything and create one fix backlog”

## Expected Agent Behavior

When the skill is followed correctly, the agent should:

1. Define the target scope
2. Split the repository into review lanes
3. Audit all lanes, not just the interesting ones
4. Append confirmed findings into the same issue
5. Continue with the remaining lanes
6. Stop only after coverage is exhausted

## Forced Pause Behavior

If the model hits context, tool, or external system limits, it should not pretend the audit is done.

It should leave:

- completion percentage
- completed scope
- remaining scope
- exact next module/file
- canonical issue URL

## For ChatGPT and Codex-Like Agents

This skill is especially helpful for agents that are:

- highly capable in local reasoning
- good at producing polished milestone summaries
- prone to deciding that “enough has been done” before the requested audit scope is fully covered

That includes **Codex**, **ChatGPT-style coding assistants**, and similar agents operating in long audit or review loops.

## License

MIT
