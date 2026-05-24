# Hook Installation

Hooks are runtime-specific. Use [`core/hooks/generic/`](../core/hooks/generic/) for portable shell examples and runtime adapter folders for platform-specific wiring. The hook catalog is [`core/hooks/README.md`](../core/hooks/README.md).

The end-to-end compaction lifecycle these hooks implement is in [`LIFECYCLE.md`](../LIFECYCLE.md).

## Recommended hook points

| Hook point | Purpose | Canonical protocol |
| --- | --- | --- |
| Session start | Run `bd prime` and load durable task / memory context. | [`core/protocols/bd-and-memory.md`](../core/protocols/bd-and-memory.md) |
| Pre-tool use | Apply `native-tool` / `rtk-safe` / `raw-required` command policy. | [`core/protocols/rtk-command-policy.md`](../core/protocols/rtk-command-policy.md) |
| Pre-compaction | Snapshot transcript into bd memory and per-task comments. | [`LIFECYCLE.md`](../LIFECYCLE.md) |
| User-prompt-submit | Warn when context utilization passes `CTX_COMPACT_THRESHOLD`. | [`LIFECYCLE.md`](../LIFECYCLE.md) |
| Post-task | Store durable learnings with `bd remember`. | [`core/protocols/bd-and-memory.md`](../core/protocols/bd-and-memory.md) |
| Pre-publish | Run redaction and secret scans. | [`sanitization/prepublish-checklist.md`](../sanitization/prepublish-checklist.md) |

Do not commit runtime settings containing credentials or local paths.

## Adoption checklist

1. Install required tools from [`prerequisites.md`](prerequisites.md).
2. Choose a runtime adapter from [`../adapters/`](../adapters/).
3. Wire only the hooks supported by that runtime.
4. Keep hook scripts generic and public-safe.
5. Keep local runtime config uncommitted.
