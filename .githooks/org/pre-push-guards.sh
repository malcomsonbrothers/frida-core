#!/usr/bin/env bash
# Org pre-push release guard, vendored by org-checks scripts/install-hooks.sh into
# .githooks/org/pre-push-guards.sh and called by .githooks/pre-push with the hook's arguments
# (remote name, URL) and stdin. Do not edit the vendored copy; re-run the installer instead.
# A push to swarm/run counts its unreleased commits: those committed since the head of
# <remote>/staging (else the remote's default branch). Rebase merges rewrite SHAs, so the
# committer date, not ancestry, marks what was released. Warns at 80, refuses at 150.
# A repo's .release-guard (read at the pushed commit) may lower either: "warn N", "refuse N".
# Uses only refs git already has: no network.
set -euo pipefail
export LC_ALL=C

warn=80 refuse=150
remote=${1:-origin}

git rev-parse -q --verify "refs/remotes/$remote/swarm/run^{commit}" >/dev/null || exit 0
release=""
for r in "refs/remotes/$remote/staging" "$(git symbolic-ref -q "refs/remotes/$remote/HEAD" || :)" \
  "refs/remotes/$remote/main" "refs/remotes/$remote/master"; do
  if [ -n "$r" ] && git rev-parse -q --verify "$r^{commit}" >/dev/null; then release=$r; break; fi
done
[ -n "$release" ] || exit 0
since=$(git log -1 --format=%cI "$release")

status=0
while read -r _local_ref local_sha remote_ref _remote_sha; do
  [ "$remote_ref" = refs/heads/swarm/run ] || continue
  case $local_sha in *[!0]*) ;; *) continue ;; esac # deleting swarm/run
  w=$warn r=$refuse
  while read -r key value rest; do
    case $key in ''|'#'*) continue ;; esac
    if ! [[ $value =~ ^[0-9]+$ ]] || [ -n "$rest" ]; then echo "release-guard: ignoring .release-guard line: $key $value $rest" >&2
    elif [ "$key" = warn ]; then [ "$value" -ge "$w" ] || w=$value
    elif [ "$key" = refuse ]; then [ "$value" -ge "$r" ] || r=$value
    else echo "release-guard: ignoring .release-guard line: $key $value" >&2; fi
  done < <(git show "$local_sha:.release-guard" 2>/dev/null | tr -d '\r' || :)
  n=$(git rev-list --count --since="$since" "$local_sha")
  [ "$n" -ge "$w" ] || continue
  msg="$n unreleased commits on swarm/run: cut a staging release now; GitHub refuses rebase-merge past ~100"
  echo "release-guard: $msg" >&2
  echo "release-guard: counted since ${release#refs/remotes/} at $since (git fetch if that is stale)" >&2
  if [ "$n" -ge "$r" ]; then
    echo "release-guard: push refused at $r or more; release swarm/run to staging first" >&2
    status=1
  fi
done
exit "$status"
