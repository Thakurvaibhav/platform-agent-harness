# Token Optimization (rtk)

[`rtk`](https://github.com/rtk-ai/rtk) is a CLI proxy that compresses verbose command output by 60–90%. Prefix a command invoked through the runtime's shell-execute tool when it is read-only **and** its compressed output is sufficient for what you need. Both halves are required: read-only alone is not eligibility, because a compressed render or diff you are about to reason over is no longer the thing you measured.

Before every shell call, classify the command as `native-tool`, `rtk-safe`, or `raw-required`:

- **`native-tool`**: use the agent's built-in `Read`, `Grep`, `Glob`, `LS` tools instead of shell.
- **`rtk-safe`**: simple read-only verbose command; prefix with `rtk`.
- **`raw-required`**: mutating, interactive, exact-output-sensitive, or piped / chained command; run raw.

## Always prefix with `rtk`

- **Git read-only**: `rtk git status`, `rtk git diff`, `rtk git log`, `rtk git show`, `rtk git branch`
- **GitHub CLI read-only**: `rtk gh pr list`, `rtk gh pr view`, `rtk gh issue list`, `rtk gh run view` — **not** `gh pr diff`, see below
- **Containers / k8s read-only**: `rtk docker ps`, `rtk docker logs`, `rtk kubectl get`, `rtk kubectl describe`, `rtk kubectl logs`, `rtk kubectl top`
- **Build / test / check**: `rtk cargo test`, `rtk cargo build`, `rtk npm test`, `rtk pnpm test`, `rtk pytest`, `rtk go test`, `rtk go build`, `rtk tsc`, lint commands
- **Helm read / check**: `rtk helm template`, `rtk helm lint`, `rtk helm dependency build`, `rtk helm show values`
- **Other read / check**: `rtk terraform plan`, `rtk gcx --agent ... -o json`

## Do NOT prefix with `rtk`

- **`gh pr diff` — never.** `rtk` truncates it almost silently: measured on a 9-file PR it emitted 7 files and 25 hunks against the raw 18 diff markers and 32 hunks, dropping two files outright and 26 additions inside another. It does print `... (more changes truncated)`, but the follow-up it suggests (`rtk git diff --no-compact`) is the wrong command for `gh` input. A reviewer working from the truncated diff silently skips whole files. `rtk gh pr view --json ...` is byte-identical to raw and stays on the allowlist.
- **When the output IS the evidence, run it raw.** A render, a plan, a full manifest — anything you will diff, attach as proof, or parse — must not be compressed. Dropping a manual `rtk` is not enough where an autoprefix hook is wired: prefix the command with `RTK_DISABLE=1` instead, which both hooks under *Hooked automation* bail on.
- Mutating commands where exact output matters (`git push`, `git commit`).
- Commands piped into other commands or shell substitution (`$(...)`, `|`, non-`cd` `&&` chains).
- Interactive commands or ones that need a TTY.
- Exact-output commands where summarized output would lose required details.
- Commands already handled by native tools (`Read`, `Grep`, `Glob`, `LS`) — use the tool instead.

## Fallback

If `rtk <cmd>` fails, retry once without the `rtk` prefix and proceed.

## Hooked automation

The PreToolUse hook at [`core/hooks/factory-droid/rtk-autoprefix.py`](../hooks/factory-droid/rtk-autoprefix.py) automatically inserts `rtk` for matching commands, preserving leading `env=` assignments and wrappers (`sudo`, `time`, `nice`). [`core/hooks/generic/rtk-wrapper.sh`](../hooks/generic/rtk-wrapper.sh) is the portable shell equivalent. Both bail out cleanly when `rtk` is not installed, when the command is `gh pr diff`, and on a leading `RTK_DISABLE=1`.

## Why this matters

A 30-minute infra session can pump 100k+ tokens of `kubectl describe`, `helm template`, and `git diff` into context. `rtk` keeps the decision-relevant parts and drops boilerplate. The agent invokes commands normally; `rtk` rewrites the output before the model sees it.
