#!/usr/bin/env bash
# env.sh — the ONE place that knows where this machine's work lives.
#
# WHY THIS FILE EXISTS
# -------------------
# These pins used to be scattered: the runtime's settings JSON, ~/.zshenv,
# ~/.bashrc, ~/.bash_profile, and a launcher default. Five places to edit when a
# path changed — and the failure mode is not "it breaks". It is that you edit one
# and the other four silently disagree, so a hook, a cron job, and an interactive
# shell each resolve a different memory database and none of them errors.
# Changing employer, laptop, or directory layout should be an edit HERE, not a
# grep across the harness.
#
# HOW IT IS WIRED
# ---------------
# Source it once from each shell profile that exists:
#     . "$HOME/.agent-knowledge/env.sh"
# and never re-export these variables anywhere else. A raw `export BEADS_DB=` in
# a profile is sourced AFTER this file and silently overrides it — correct today,
# wrong the moment this file is edited, which defeats the point.
#
# Scripts that need these values should source this file rather than re-deriving
# paths, because hooks and cron do not reliably inherit a login shell.
#
# THE ONE UNAVOIDABLE DUPLICATE
# -----------------------------
# Some runtimes configure the agent's environment from a JSON file, and JSON
# cannot source a shell file. Where a runtime carries a literal copy of BEADS_DB
# (Claude Code's `settings.json` → `env.BEADS_DB`, for example), that literal must
# be updated in the same edit as WORK_ROOT below. It is the only duplicate this
# design cannot remove — so it is documented rather than forgotten.

# Root that holds the git repos and the bd hive.
export WORK_ROOT="${WORK_ROOT:-$HOME/Work/git-repos}"

# Canonical bd hive. Lives BESIDE the repos, never inside one — a hive nested in
# a repo gets committed by accident and dies with that repo when you change jobs.
# bd does not search for its database; BEADS_DB is the only thing that finds it,
# so moving WORK_ROOT means moving the hive too.
export BEADS_DB="${BEADS_DB:-$WORK_ROOT/.beads}"

# Deployed knowledge home: references/, orgs/, scripts/, metrics/, reading/.
# Any path works — knowledge-search.sh resolves this home relative to itself.
export HARNESS_HOME="${HARNESS_HOME:-$HOME/.agent-knowledge}"

# Domain docs tree searched by knowledge-search.sh. Instance-specific; repoint it
# at the new job rather than relocating the tree.
export HARNESS_DOCS="${HARNESS_DOCS:-$HOME/Work/docs}"

# Issue tracker base URL for create-pr's ticket links, e.g. https://<org>.atlassian.net.
# No default: consumers must degrade gracefully (omit the link) when it is empty.
export JIRA_BASE_URL="${JIRA_BASE_URL:-}"

# Active knowledge tier: org short name, lowercase — see core/protocols/knowledge-tiers.md.
# INVARIANT: labels where writes go; must NEVER narrow a read.
export ACTIVE_ORG="${ACTIVE_ORG:-}"
