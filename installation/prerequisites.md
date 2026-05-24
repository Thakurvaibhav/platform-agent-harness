# Prerequisites

The harness depends on a small set of tools. Each link points to the upstream project.

## Required

| Tool | What it does in the harness | Upstream / install |
| --- | --- | --- |
| `git` | Source control for the harness and your repos. | <https://git-scm.com/downloads> |
| `jq` | JSON inspection in hooks, validators, and examples. | <https://jqlang.github.io/jq/download/> |
| `yq` | YAML inspection for ArgoCD / Helm / values workflows. | <https://github.com/mikefarah/yq#install> |
| Python 3 / `uv` / `pipx` | Runs hooks, validators, many CLIs. | <https://www.python.org/downloads/>, <https://docs.astral.sh/uv/>, <https://pipx.pypa.io/> |
| **`bd`** (Beads) | Durable task ledger and memory substrate. | <https://github.com/steveyegge/beads> · see [`tools/bd/README.md`](../tools/bd/README.md) |
| **`graphify`** | Repo knowledge graph for architecture and dependency questions. | <https://github.com/safishamsi/graphify> · see [`tools/graphify/README.md`](../tools/graphify/README.md) |
| **`rtk`** | Compresses verbose CLI output to save tokens. | <https://github.com/rtk-ai/rtk> · see [`tools/rtk/README.md`](../tools/rtk/README.md) |

## Optional platform tools

| Tool | When to install | Upstream / install |
| --- | --- | --- |
| `kubectl` | Read-only Kubernetes debugging. | <https://kubernetes.io/docs/tasks/tools/> |
| `helm` | Chart authoring, rendering, scanning. | <https://helm.sh/docs/intro/install/> |
| `argocd` (CLI) | GitOps app inspection and enablement. | <https://argo-cd.readthedocs.io/en/stable/cli_installation/> |
| `kustomize` | Manifest overlays. | <https://kubectl.docs.kubernetes.io/installation/kustomize/> |
| `gh` | GitHub PR / issue / run workflows. | <https://cli.github.com/> |
| `pre-commit` | Local pre-commit hooks. | <https://pre-commit.com/#install> |
| `gitleaks` | Secret scanning in the sanitization gate. | <https://github.com/gitleaks/gitleaks#installing> |
| `trufflehog` | Alternative / additional secret scanner. | <https://github.com/trufflesecurity/trufflehog#installation> |

## Optional observability tools

| Tool | When to install | Upstream / install |
| --- | --- | --- |
| **`gcx`** | Grafana / Grafana Cloud CLI for cross-signal RCA. | <https://github.com/grafana/gcx> · see [`tools/gcx/README.md`](../tools/gcx/README.md) |
| Grafana MCP | First-choice integration when running an MCP-capable runtime. | <https://github.com/grafana/mcp-grafana> |
| Atlassian MCP | Jira / Confluence integration for task planning. | <https://www.atlassian.com/platform/remote-mcp-server> |

After installing `gcx`, drop the 18-skill bundle into the cross-tool `~/.agents/skills` directory:

```bash
gcx skills install --all
```

Most adapters (Claude Code, Codex CLI, OpenCode) auto-discover skills from `~/.agents/skills`. For runtimes that look elsewhere, use `gcx skills install --dir <path>` and point it at the runtime's skill directory (see your adapter README).

## Agent runtimes

Use any CLI-based agent runtime. The harness ships adapters for:

- [Aider](https://aider.chat/) → [`adapters/aider/README.md`](../adapters/aider/README.md)
- [Claude Code](https://code.claude.com/) → [`adapters/claude-code/README.md`](../adapters/claude-code/README.md)
- [Codex CLI](https://developers.openai.com/codex/cli) → [`adapters/codex-cli/README.md`](../adapters/codex-cli/README.md)
- [Factory Droid](https://factory.ai/) → [`adapters/factory-droid/README.md`](../adapters/factory-droid/README.md)
- [Goose](https://block.github.io/goose/) → [`adapters/goose/README.md`](../adapters/goose/README.md)
- [OpenCode](https://opencode.ai/) → [`adapters/opencode/README.md`](../adapters/opencode/README.md)

## Verify

```bash
git --version
jq --version
yq --version
python3 --version
bd --version
graphify --help
rtk --help
```

Optional:

```bash
kubectl version --client
helm version
argocd version --client
gh --version
pre-commit --version
gcx --version
trufflehog --version
gitleaks version
```
