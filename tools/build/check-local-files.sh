#!/bin/bash

TARGET_REF=${1:-.}
A=$(
  git status --porcelain --ignore-submodules=all "$TARGET_REF" |
    grep -Ev '^[MADRC] ' |
    grep -Ev '^(DD )|gitmodules|manifest|\.container_ready' |
    awk '{print $2}'
)

if [[ -n "$A" ]]; then
    printf "=================================================================\n"
    printf "Failing compilation due to presence of locally modified files/conflicting changes:\n"
    printf "%s\n" "$A"
    echo
    printf "Local changes (git diff output) follow:\n"
    echo

    # Temporary hack until manifest generation no longer relies on checked-in files
    git --no-pager diff --ignore-submodules=all "$TARGET_REF"

    echo
    printf "**** This typically means the tree needs to be rebased and locally generated files committed ****\n"
    printf "=================================================================\n"
    exit 1
fi

echo "No uncommitted locally modified files"
exit 0