#!/usr/bin/env bash
# codex-dispatch.sh — dispatch a headless Codex specialist worker (subagent parity).
#
# Codex has no native subagent type; this wraps `codex exec` with a specialist
# role prompt + the standard hive preamble, giving Claude-style delegation.
#
# Single source of truth: the role definitions in <AGENTS_DIR>/<name>.md are
# harness-neutral in their body (they reference shared-protocols-core.md + bd), so
# we reuse them directly and strip the Claude-only YAML frontmatter. A Codex-only
# override may be placed in <CODEX_AGENTS_DIR>/<name>.md (takes priority).
#
# Usage:
#   codex-dispatch.sh <specialist> "<task>" [target-dir]
#   codex-dispatch.sh helm-engineer "Bump <chart> to 1.2.0" /path/to/repo
#
# Sandbox (CODEX_SANDBOX env var, NOT a positional arg: every caller passes
# <specialist> "<task>" <dir> positionally and must keep working untouched):
#   unset | full   default. No --sandbox flag, so codex uses its own default.
#                  That is danger-full-access: the worker may write anywhere the
#                  user can. Unchanged behaviour for every existing caller.
#   bounded        workspace-write + network + a writable allowlist. Network stays
#                  ON, so helm/gh/git/curl work. Opt-in only.
#                  Writable: the target dir, /tmp and $TMPDIR (codex's own
#                  defaults), plus the allowlist below. NOT writable: $HOME, the
#                  knowledge home, the runtime's own config dirs, or any repo
#                  outside the target dir. So this bounds TAMPERING, not reading:
#                  reads stay open everywhere and the network is on, so it is not
#                  an exfiltration control.
#
#   CODEX_SANDBOX=bounded codex-dispatch.sh general-engineer "audit X" /path
#
# What `bounded` costs, measured on codex-cli 0.153.4, not guessed:
#   - `git commit` fails. codex write-protects .git even inside the workspace.
#   - A nested codex-dispatch.sh fails; a worker cannot write the codex config
#     dir. The depth ceiling already discourages that, this hard-fails it.
#   - `read-only` is NOT offered: bd takes a LOCK on open, so read-only breaks
#     `bd prime` itself and the worker starts with no hive at all.
#   - Replayed green: helm dep build (http + oci), helm template, gh pr view,
#     gh pr diff, git clone, bd prime, bd memories, knowledge-search.sh, learn.sh,
#     kubectl, gcloud auth list, rtk. The capture gate fires identically under
#     both modes (same prompt, controlled comparison).
#
# Fan-out (run several, each on a DISTINCT bd task, to avoid hive write races):
#   codex-dispatch.sh A "taskA" & codex-dispatch.sh B "taskB" & wait
#
# Environment:
#   AGENTS_DIR         — directory containing <name>.md role definitions
#                        (default: ~/.claude/agents for Claude Code installs,
#                         or core/agents/ within the harness repo)
#   CODEX_AGENTS_DIR   — optional override directory for Codex-specific roles
#                        (default: ~/.agent-knowledge/codex-agents)
#   KNOWLEDGE_HOME     — path to knowledge references dir
#                        (default: ~/.agent-knowledge/references)
#   CODEX_SANDBOX      : full (default) or bounded (see above)
#   BEADS_DB           : bd hive directory, required by CODEX_SANDBOX=bounded
#   HARNESS_DEPTH      — dispatch-hop counter, managed by this script (see below)
set -euo pipefail

SPECIALIST="${1:?usage: codex-dispatch.sh <specialist> \"<task>\" [dir]}"
TASK="${2:?missing task}"
DIR="${3:-$PWD}"

# Depth ceiling. HARNESS_DEPTH counts dispatch hops already taken: a worker
# launched from the main session or a sub-agent runs at 1, its own worker at 2.
# Dispatching at >=2 would create hop 3 — refused. Without this, a worker that
# fans out is unbounded recursion with no visibility and no budget accounting.
#
# The cap is a backstop, not the primary control: a worker running a role whose
# prompt describes fan-out will try to fan out. Tell it not to, in the prompt.
HARNESS_DEPTH="${HARNESS_DEPTH:-0}"
if [ "$HARNESS_DEPTH" -ge 2 ]; then
  echo "codex-dispatch: depth limit reached (HARNESS_DEPTH=$HARNESS_DEPTH, max 2)." >&2
  echo "  Workers at depth 2 may not spawn further workers. Do the work inline" >&2
  echo "  or return findings up so the orchestrator can re-dispatch." >&2
  exit 3
fi
export HARNESS_DEPTH=$((HARNESS_DEPTH + 1))

# Sandbox mode. Validated against a closed set: an unrecognised value is a hard
# error, never a silent fall-through to full access. A typo must not quietly hand
# a worker the whole filesystem.
SANDBOX_ARGS=()
case "${CODEX_SANDBOX:-full}" in
  full) ;;   # no flag: codex's own default (danger-full-access)
  bounded)
    : "${BEADS_DB:?CODEX_SANDBOX=bounded needs BEADS_DB (source agent-knowledge/env.sh)}"
    HIVE="$(cd "$BEADS_DB" 2>/dev/null && pwd -P)" \
      || { echo "codex-dispatch: BEADS_DB=$BEADS_DB is not a readable directory" >&2; exit 4; }
    WRITABLE=("$HIVE")
    # Each candidate below is here because a real worker command failed without it,
    # and each is added ONLY if it exists, so a machine without that tool gets a
    # working sandbox instead of a root pointing at nothing:
    #   helm cache    -> `helm dep build` cannot refresh a repo index, which then
    #                    fails `helm template`, the rendered-proof step. On Linux
    #                    that cache lives under ~/.cache, already covered below.
    #   gcloud config -> gcloud writes a log file before doing anything else.
    #   .cache        -> shared cache dir for assorted CLIs.
    for _root in "$HOME/Library/Caches/helm" "$HOME/.config/gcloud" "$HOME/.cache"; do
      if [ -d "$_root" ]; then WRITABLE+=("$_root"); fi
    done
    _json=""
    for _root in "${WRITABLE[@]}"; do _json="$_json,\"$_root\""; done
    SANDBOX_ARGS=(
      --sandbox workspace-write
      -c sandbox_workspace_write.network_access=true
      -c "sandbox_workspace_write.writable_roots=[${_json#,}]"
    )
    ;;
  *)
    echo "codex-dispatch: CODEX_SANDBOX='$CODEX_SANDBOX' is not valid. Use 'full' or 'bounded'." >&2
    echo "  Refusing to guess: an unrecognised value will NOT fall back to full access." >&2
    exit 4
    ;;
esac

AGENTS_DIR="${AGENTS_DIR:-$HOME/.claude/agents}"
CODEX_AGENTS_DIR="${CODEX_AGENTS_DIR:-$HOME/.agent-knowledge/codex-agents}"
KNOWLEDGE_HOME="${KNOWLEDGE_HOME:-$HOME/.agent-knowledge/references}"

CODEX_OVERRIDE="$CODEX_AGENTS_DIR/$SPECIALIST.md"
MAIN_ROLE="$AGENTS_DIR/$SPECIALIST.md"
if   [ -f "$CODEX_OVERRIDE" ]; then ROLE_FILE="$CODEX_OVERRIDE"
elif [ -f "$MAIN_ROLE"      ]; then ROLE_FILE="$MAIN_ROLE"
else
  echo "unknown specialist '$SPECIALIST'. available:" >&2
  { ls "$AGENTS_DIR" 2>/dev/null; ls "$CODEX_AGENTS_DIR" 2>/dev/null; } \
    | sed 's/\.md$//' | sort -u | sed 's/^/  - /' >&2
  exit 2
fi

# Strip YAML frontmatter (the leading ---...--- block) — runtime-specific metadata.
ROLE_BODY="$(awk 'NR==1 && /^---[[:space:]]*$/{f=1; next} f && /^---[[:space:]]*$/{f=0; next} !f' "$ROLE_FILE")"

PREAMBLE="## Standard preamble
- Run \`bd prime --memories-only\` first to load the shared hive memory.
- Read $KNOWLEDGE_HOME/shared-protocols-core.md for shared protocols (or equivalent),
  and $KNOWLEDGE_HOME/code-quality.md before writing code.
- Search prior art: knowledge-search.sh <keywords>; cite [learnings-<file>.md#<N>].
- Prefix verbose read-only shell with rtk. Never prefix mutating or piped commands.
- Before finishing, persist non-obvious findings: bd remember \"<insight>\" --key <domain>/<category>/<topic>.
- End with a concise result and a 'Verify by:' note."

FULL_PROMPT="$ROLE_BODY

$PREAMBLE

## Your task
$TASK"

# --skip-git-repo-check: codex exec otherwise refuses non-git target dirs.
# < /dev/null: codex exec HANGS on "Reading additional input from stdin..." if stdin
# stays open (inherited from the caller). Closing it here means callers can't get this
# wrong — the dispatcher is the single place that has to remember.
exec codex exec --skip-git-repo-check "${SANDBOX_ARGS[@]+"${SANDBOX_ARGS[@]}"}" \
  --cd "$DIR" "$FULL_PROMPT" < /dev/null
