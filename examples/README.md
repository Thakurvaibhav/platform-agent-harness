# Worked Examples

Two end-to-end stories showing how the pieces fit together in real platform engineering work. Both use synthetic placeholders only.

| Example | What it demonstrates |
| --- | --- |
| [helm-chart-upgrade.md](helm-chart-upgrade.md) | Full Helm subchart upgrade flow — research, render-diff, immutable-field check, PR, post-merge validation. Exercises `task-planner` → `tool-researcher` → `helm-engineer` → `pr-reviewer`. |
| [alert-investigation.md](alert-investigation.md) | A firing alert triaged via `gcx` bundled skills, cross-signal RCA, root-cause captured as `bd remember`. Exercises the observability bundle (`investigate-alert` → `debug-with-grafana`) plus the bd memory lifecycle. |
