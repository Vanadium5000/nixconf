---
name: patchright
description: Use the repo-local patchright browser automation workflow for account-session UI inspection, proxy-aware browser handoffs, console/network debugging, and Patchright tests.
allowed-tools: Bash(patchright:*) Bash(npm:*) Bash(node:*)
---

# Patchright Browser Automation

This is a project-owned skill, not a `skills.sh` managed copy. Use it for account-creator UI inspection and account-session debugging where the browser must match the app's Patchright/proxy behavior.

## Repo Rule

- Use the system `patchright` command directly. If PATH lookup is ambiguous, run `/run/current-system/sw/bin/patchright`; do not fall back to `npm exec`, `npx`, or the misspelled `patchwright` command.
- Prefer proxy-aware sessions for account, Roblox, ChatGPT, Codex, and proxy-quality debugging.
- Use backend-generated commands when session fidelity matters; they carry the same proxy, storage state, profile path, user agent, locale, and callback bypass rules as the backend launch path.
- When a task needs durable E2E code or test-suite structure instead of ad-hoc inspection, load the repo-local `patchright-automation-expert` skill.
- Do not commit browser state, cookies, traces, videos, or screenshots artifacts.

## Fast Paths

```bash
# Inspect the running app UI.
patchright open http://127.0.0.1:5173
patchright snapshot
patchright console
patchright network

# Ask the backend for a persisted account browser handoff.
npm run agent:api -- account-command <account-id>

# Ask the backend for a listed proxy browser handoff.
npm run agent:api -- proxy-command <proxy-id>

# Ask the backend to choose a proxy using account-generation selection.
npm run agent:api -- proxy-command --mode=least-used --service=chatgpt

# Open a retained backend Patchright browser after backend-side proxy selection.
npm run agent:api -- proxy-open --mode=least-used --service=chatgpt
```

## Proxy-First Account Debugging

1. Start with `npm run agent:api -- summary` to identify jobs, accounts, failures, and placeholders.
2. For one account, fetch `npm run agent:api -- account-llm <account-id>` before opening browsers.
3. For ChatGPT or Roblox browser state, run `npm run agent:api -- account-command <account-id>` and execute the returned command.
4. For raw proxy inspection, run `npm run agent:api -- proxy-command <proxy-id>` or `npm run agent:api -- proxy-command --mode=least-used`.
5. Use `patchright console`, `patchright network`, `patchright snapshot`, and targeted `patchright eval` before changing selectors or backend behavior.

## UI Inspection

```bash
patchright open http://127.0.0.1:5173
patchright snapshot
patchright click e15
patchright type "search text"
patchright press Enter
patchright console error
patchright network
patchright close
```

Close sessions after inspection unless a visible retained browser is the evidence being debugged.

## Durable Test Runs

```bash
npm run --prefix apps/frontend test:e2e
```

Convert proven interactive flows into normal Patchright tests only when the task asks for durable coverage. Avoid sleeps, weakened assertions, and broad selector guesses. For repeated test authoring, flaky suites, or Page Object/fixture design, switch to the repo-local `patchright-automation-expert` skill.
