# rtk

`rtk` (Rust Token Killer) is a CLI proxy that compresses verbose command output before it reaches an agent's context, cutting typical token consumption by 60–90% on read-only dev commands.

- Upstream repo: <https://github.com/rtk-ai/rtk>

## Why the harness uses it

- **Token economics.** A 30-minute infra session can pump hundreds of thousands of tokens of `kubectl describe`, `helm template`, and `git diff` into context. `rtk` keeps the decision-relevant parts and drops boilerplate.
- **Same UX for the agent.** The agent invokes the command normally; `rtk` rewrites the output before the model sees it.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | bash
```

Or build from source (single Rust binary, zero dependencies) per the [rtk README](https://github.com/rtk-ai/rtk#install).

Verify:

```bash
rtk --help
```

## Harness command policy

Before every shell call, classify the command:

| Class | Action |
| --- | --- |
| `native-tool` | Use the agent's built-in `Read` / `Grep` / `Glob` / `LS` tools instead of shell. |
| `rtk-safe` | Simple read-only verbose command — prefix with `rtk`. |
| `raw-required` | Mutating, piped, chained, interactive, or exact-output-sensitive — run raw. |

## rtk-safe allowlist

```bash
rtk git diff
rtk gh pr diff <url>
rtk kubectl describe pod <pod> -n <ns>
rtk helm template <release> <chart>
```

Expanded allowlist:

- Git read-only: `status`, `diff`, `log`, `show`, `branch`
- GitHub read-only: `pr list`, `pr view`, `pr diff`, `issue list`, `issue view`, `run view`
- Kubernetes read-only: `get`, `describe`, `logs`, `top`
- Containers read-only: `docker ps`, `docker logs`
- Helm read/check: `template`, `lint`, `dependency build`, `show values`
- Build/test/check: `pytest`, `npm test`, `pnpm test`, `go test`, `cargo test`, `tsc`, lint commands
- Infra planning: `terraform plan`
- Observability reads: `gcx --agent ... -o json`

## raw-required denylist

Keep raw — do **not** wrap in `rtk`:

- `git commit`, `git push`
- Mutating Kubernetes or Helm commands
- Commands with `|`, `&&`, `||`, `;`, command substitution, or process substitution
- Interactive commands
- Commands whose exact output is parsed by another command

See [`core/protocols/rtk-command-policy.md`](../../core/protocols/rtk-command-policy.md) for the canonical rules.

## Hook integration

The [`core/hooks/factory-droid/rtk-autoprefix.py`](../../core/hooks/factory-droid/rtk-autoprefix.py) hook auto-inserts `rtk` for allowlisted commands while preserving `sudo` / `env=` / `time` wrappers. The portable shell equivalent is [`core/hooks/generic/rtk-wrapper.sh`](../../core/hooks/generic/rtk-wrapper.sh).
