#!/bin/sh

eval $(
	zz_args "Prune remote-tracking references that no longer exist on the remote" $0 "$@" <<-help
		- remote remote     remote to prune (default: all remotes)
	help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

remotes="${remote:-$(git remote)}"

for r in $remotes; do
	zz_log i "Pruning stale remote-tracking references for $r"
	git remote prune "$r"
done

zz_log s "Remote-tracking references pruned."
