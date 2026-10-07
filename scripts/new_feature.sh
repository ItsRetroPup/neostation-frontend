#!/usr/bin/env bash
# Creates a git worktree for experimenting with a feature in its own folder.
#
#   scripts/new_feature.sh <name> [base]
#
# - <name>  short feature name, e.g. steamgriddb
# - [base]  branch or commit to start from (default: the current HEAD)
#
# The worktree is created next to this checkout as ../neostation-<name> on a
# new branch feature/<name>. Each worktree is a full checkout sharing this
# repository's history, so features can be built and switched independently
# without stashing.
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: $0 <name> [base]" >&2
  exit 1
fi

name="$1"
base="${2:-HEAD}"
repo_root="$(git rev-parse --show-toplevel)"
worktree="$(dirname "$repo_root")/neostation-$name"
branch="feature/$name"

if [ -e "$worktree" ]; then
  echo "Folder already exists: $worktree" >&2
  exit 1
fi

if git show-ref --verify --quiet "refs/heads/$branch"; then
  # The branch exists already (e.g. pushed from another machine): reuse it.
  git worktree add "$worktree" "$branch"
else
  git worktree add -b "$branch" "$worktree" "$base"
fi

(cd "$worktree" && flutter pub get)

cat <<MSG

Worktree ready: $worktree (branch $branch)

Run a side-by-side build from it with a flavor, for example:
  cd "$worktree"
  flutter run --dart-define=NEOSTATION_FLAVOR=pup

Remove it when the feature is merged or dropped:
  git worktree remove "$worktree"
MSG
