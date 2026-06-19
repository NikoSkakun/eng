#!/usr/bin/env bash
# Stop hook — auto-integrate Claude's changes (plain git, no PR).
#
# When Claude finishes a turn and has left uncommitted changes in this repo,
# commit them on a fresh `claude/auto-<timestamp>` branch, then merge that
# branch into `main` and push both to origin (pushes are best-effort).
#
# Installed by .claude/settings.json (Stop hook). Review/disable via `/hooks`.
#
# Deliberately NOT `set -e`: a failed push must never abort mid-way and strand
# the repo on the wrong branch. Each remote step is best-effort and logged; the
# local commit + merge always complete so changes land on local main regardless.
set -uo pipefail

# No TTY in a hook — fail fast on auth instead of hanging on a prompt.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"

note() { printf 'auto-merge: %s\n' "$*" >&2; }

# Drain the hook's JSON on stdin (unused) so nothing blocks on the pipe.
cat >/dev/null 2>&1 || true

cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

main_branch="main"

# Only act when on main, so an intentional feature-branch session isn't
# hijacked. Each run ends back on main, so this stays consistent across turns.
branch_now="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [ "$branch_now" != "$main_branch" ]; then
  note "on '$branch_now', not $main_branch — skipping"
  exit 0
fi

# Nothing to integrate if the working tree is clean.
[ -n "$(git status --porcelain)" ] || exit 0

ts="$(date +%Y%m%d-%H%M%S)"
branch="claude/auto-$ts"

# Carry the working-tree changes onto a fresh branch and commit them there.
if ! git checkout -b "$branch" >/dev/null 2>&1; then
  note "could not create branch $branch — leaving changes untouched"
  exit 0
fi
git add -A
if ! git commit -q -m "chore: automated changes from Claude Code ($ts)"; then
  note "nothing to commit / commit failed — returning to $main_branch"
  git checkout -q "$main_branch" 2>/dev/null || true
  git branch -D "$branch" >/dev/null 2>&1 || true
  exit 0
fi
note "committed on $branch"

# Push the branch (best effort — local integration proceeds regardless).
if git push -u origin "$branch" >/dev/null 2>&1; then
  note "pushed $branch"
else
  note "could not push $branch (continuing; push later)"
fi

# Merge into main — the integration step; always done locally.
if ! git checkout -q "$main_branch"; then
  note "could not switch to $main_branch — left changes committed on $branch"
  exit 0
fi
if git merge --no-ff -q -m "Merge $branch into $main_branch" "$branch"; then
  note "merged $branch into $main_branch"
else
  note "merge conflict — aborting; $branch keeps the changes for manual review"
  git merge --abort 2>/dev/null || true
  exit 0
fi

# Push main (best effort).
if git push origin "$main_branch" >/dev/null 2>&1; then
  note "pushed $main_branch"
else
  note "could not push $main_branch (push later)"
fi

exit 0
