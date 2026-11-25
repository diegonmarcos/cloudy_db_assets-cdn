#!/usr/bin/env bash
# Asset-wipe guard (#1913): fails when any commit in a range deletes more than LIMIT files
# under b-Media, b_Media or b-Projects. On 2026-10-04 a commit made with an empty index
# removed the whole tree and every page lost its images.
#   guard-asset-wipe.sh <base> <head>   check every commit in base..head (merges vs first parent)
#   guard-asset-wipe.sh --self-test     build throwaway repos: wipe must fail, small delete must pass
# Needs only trees (works on blob-less clones).
set -euo pipefail
LIMIT="${LIMIT:-50}"
DIRS=(b-Media b_Media b-Projects)

check_range() {
  local base="$1" head="$2" bad=0 c n
  if [ "$base" = "0000000000000000000000000000000000000000" ] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    base="$(git rev-list --max-parents=0 "$head" | tail -1)"; base="$base^"
    git rev-parse -q --verify "$base" >/dev/null || { echo "guard: no base, checking head only"; base="$head^"; }
  fi
  for c in $(git rev-list "$base..$head"); do
    n="$(git diff-tree -r --no-renames --diff-filter=D --name-only --no-commit-id "$c^1" "$c" -- "${DIRS[@]}" 2>/dev/null | wc -l || true)"
    git rev-parse -q --verify "$c^1" >/dev/null || n=0
    if [ "$n" -gt "$LIMIT" ]; then
      echo "::error::commit $c deletes $n files under ${DIRS[*]} (limit $LIMIT)"; bad=1
    else
      echo "ok   $c deletes $n (limit $LIMIT)"
    fi
  done
  return "$bad"
}

self_test() {
  d="$(mktemp -d)"; trap "rm -rf $d" EXIT
  cd "$d"; git init -q .; git config user.email t@t; git config user.name t
  mkdir -p b-Media b_Media b-Projects other
  for i in $(seq 1 120); do echo "$i" > "b-Media/f$i.txt"; done
  for i in $(seq 1 10); do echo "$i" > "b_Media/g$i.txt"; echo "$i" > "other/o$i.txt"; done
  git add -A; git commit -qm base; local base; base="$(git rev-parse HEAD)"
  git rm -q b-Media/f1.txt b-Media/f2.txt b_Media/g1.txt; git commit -qm small; local small; small="$(git rev-parse HEAD)"
  # mutation: empty-index commit that wipes everything
  git rm -rq b-Media b_Media; git commit -qm wipe; local wipe; wipe="$(git rev-parse HEAD)"
  git reset -q --hard "$small"; git rm -rq other; git commit -qm other-only; local other; other="$(git rev-parse HEAD)"
  local rc=0
  check_range "$base" "$small" >/dev/null || { echo "SELF-TEST FAIL: small delete flagged"; rc=1; }
  check_range "$small" "$other" >/dev/null || { echo "SELF-TEST FAIL: delete outside asset dirs flagged"; rc=1; }
  if check_range "$small" "$wipe" >/dev/null 2>&1; then echo "SELF-TEST FAIL: wipe not caught (mutation survived)"; rc=1; fi
  [ "$rc" = 0 ] && echo "self-test ok: small and unrelated deletes pass, wipe fails"
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then self_test; else check_range "${1:?base}" "${2:-HEAD}"; fi
