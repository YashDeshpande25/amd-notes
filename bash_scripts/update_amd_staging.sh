#!/bin/bash
set -euo pipefail

cd /home/ydeshpan/my_repos/llvm-project

# Local amd-staging may be ahead of origin if an earlier push failed, which makes
# this fetch a rejected rewind; the upstream fetch and push below recover from it.
git fetch origin amd-staging:amd-staging || echo "origin fetch was not a fast-forward, continuing"
git fetch upstream amd-staging:amd-staging

if [ "$(git rev-parse amd-staging)" != "$(git rev-parse upstream/amd-staging)" ]; then
    echo "ERROR: local amd-staging does not match upstream/amd-staging, not pushing" >&2
    git rev-list --left-right --count amd-staging...upstream/amd-staging
    exit 1
fi

git push origin amd-staging
echo "amd-staging synced at $(git rev-parse --short amd-staging)"
