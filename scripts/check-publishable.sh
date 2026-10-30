#!/bin/bash
# Check that what is about to be published carries nothing private. Run it before a commit that is meant
# to leave this machine, or call it from a pre-commit hook.
#
#   scripts/check-publishable.sh
#
# 1. gitleaks on the working tree, and on the history once there is one. Settings: .gitleaks.toml.
#    Findings that were looked at and are fine: .gitleaksignore (one line per finding).
# 2. Patterns that must not appear in the tree: the home directory of whoever runs this, private key
#    blocks, and the strings listed in a local file that is not part of the repository:
#      ${SGL_CHECK_PATTERNS:-${XDG_CONFIG_HOME:-$HOME/.config}/sgl-check-publishable.patterns}
#    See check-publishable.patterns.example. Only file:line is printed, never the matching text.
# 3. The author and committer address of every commit must match SGL_ALLOWED_EMAIL_RE
#    (default: GitHub noreply addresses).
#
# The generated repository (repos/*/pool, db, dists) is skipped: it is never published.
# Exit status: 0 everything passed, 1 something failed, 2 a tool is missing.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass() { printf 'PASS  %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

for tool in gitleaks rg python3 git; do
    command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done

# Keep in step with the allowlist in .gitleaks.toml.
excludes=(--glob '!.git/**' --glob '!repos/*/pool/**' --glob '!repos/*/db/**' --glob '!repos/*/dists/**')

# check_pattern <label> <ripgrep regex>
check_pattern() {
    local label=$1 regex=$2 hits
    hits=$(rg --line-number --no-heading --hidden --no-messages -i "${excludes[@]}" -e "$regex" . | cut -d: -f1,2)
    if [ -n "$hits" ]; then
        bad "$label"
        printf '%s\n' "$hits" | sed -n '1,10p' | sed 's/^/        /'
        [ "$(printf '%s\n' "$hits" | wc -l)" -gt 10 ] && echo "        ..."
    else
        pass "$label"
    fi
}

# run_gitleaks <label> [extra gitleaks arguments]
run_gitleaks() {
    local label=$1 rc report=$tmp/gitleaks.json
    shift
    gitleaks detect "$@" --source . --redact --no-banner -f json -r "$report" >/dev/null 2>"$tmp/gitleaks.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass "$label"
        return
    fi
    bad "$label"
    if [ "$rc" -eq 1 ] && [ -s "$report" ]; then
        python3 -I -c '
import json, sys
for f in json.load(open(sys.argv[1]))[:10]:
    print("        %s  %s:%s" % (f["RuleID"], f["File"], f["StartLine"]))
' "$report"
    else
        sed -n '1,5p' "$tmp/gitleaks.err" | sed 's/^/        /'
    fi
}

escape() { printf '%s' "$1" | sed 's/[][\.*^$(){}?+|/]/\\&/g'; }

run_gitleaks "gitleaks: working tree" --no-git
if git rev-parse --verify -q HEAD >/dev/null; then
    run_gitleaks "gitleaks: history"
fi

check_pattern "home directory path" "$(escape "$HOME")|/home/$(escape "${USER:-$(id -un)}")/"
check_pattern "private key block" 'BEGIN [A-Z ]*PRIVATE KEY'

patterns=${SGL_CHECK_PATTERNS:-${XDG_CONFIG_HOME:-$HOME/.config}/sgl-check-publishable.patterns}
if [ -r "$patterns" ]; then
    while IFS= read -r line; do
        case $line in '' | '#'*) continue ;; esac
        check_pattern "${line%% :: *}" "${line#* :: }"
    done <"$patterns"
else
    echo "NOTE  no local pattern file ($patterns): only the built-in checks ran"
fi

if git rev-parse --verify -q HEAD >/dev/null; then
    allowed=${SGL_ALLOWED_EMAIL_RE:-'@users\.noreply\.github\.com$'}
    others=$(git log --all --format='%ae%n%ce' | sort -u | rg -v -e "$allowed")
    if [ -n "$others" ]; then
        bad "commit author/committer addresses"
        printf '%s\n' "$others" | sed 's/^/        /'
    else
        pass "commit author/committer addresses"
    fi
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "OK: nothing private found"
else
    echo "NOT publishable yet"
fi
exit "$fail"
