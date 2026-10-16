#!/usr/bin/env bash
# leak-check.sh [--staged] — fail if the repo (or the staged files) contain anything that must not
# reach a public repo: internal hosts, IPs, emails, token shapes, home-directory paths, or any
# pattern from a denylist kept OUTSIDE the repo.
#
# The denylist lives at ${HARNESS_DENYLIST:-~/.config/claude-code-harness/denylist}: one extended
# regex per line, matched case-insensitively, '#' comments allowed. It holds your organisation's
# names and domains. Keeping it out of the repo means the public repo never has to spell out what
# it forbids. A missing denylist is a failure, not a pass: without it, half the check is off.
#
# Exit 0 = clean, 1 = leaks found (each printed as file:line: pattern), 2 = setup problem.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DENY="${HARNESS_DENYLIST:-$HOME/.config/claude-code-harness/denylist}"
cd "$ROOT" || exit 2

if [ "${1:-}" = "--staged" ]; then
  mapfile -t FILES < <(git diff --cached --name-only --diff-filter=ACMR)
else
  mapfile -t FILES < <(git ls-files --cached --others --exclude-standard)
fi
# Vendored third-party code is not ours to scan (minified js-yaml trips the IP pattern), and
# LICENSE names the copyright holder on purpose.
mapfile -t FILES < <(printf '%s\n' "${FILES[@]}" | grep -v -E '^core/vendor/|^LICENSE$|^$')
[ "${#FILES[@]}" -eq 0 ] && { echo "leak-check: no files"; exit 0; }

if [ ! -r "$DENY" ]; then
  echo "leak-check: denylist not found at $DENY (create it: one regex per line; see this script's header)" >&2
  exit 2
fi

FOUND=0
scan() { # scan <label> <ERE pattern> [case-flag -i|""] [ERE of allowed matches to drop]
  local label="$1" pat="$2" ci="${3:-}" allow="${4:-}"
  local out
  out=$(grep -n -I -E $ci -- "$pat" "${FILES[@]}" 2>/dev/null) || return 0
  [ -n "$allow" ] && out=$(printf '%s\n' "$out" | grep -v -E -- "$allow")
  [ -z "$out" ] && return 0
  printf '%s\n' "$out" | sed "s/^/  [$label] /" | cut -c1-200
  FOUND=$((FOUND + $(printf '%s\n' "$out" | wc -l)))
}

# Generic patterns (safe to publish).
scan "ipv4"      '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "" '127\.0\.0\.1|0\.0\.0\.0'
scan "email"     '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "" 'noreply@anthropic\.com|@example\.(com|org)'
scan "token"     '(ghp_|gho_|glpat-|sk-|xox[bp]-|AKIA)[A-Za-z0-9_-]{12,}'
scan "home-path" '/(home|Users)/[a-z][a-z0-9_-]*/' "" '/(home|Users)/<user>/'

# Denylist patterns (private, per owner).
while IFS= read -r pat || [ -n "$pat" ]; do
  case "$pat" in ''|'#'*) continue;; esac
  scan "deny" "$pat" -i
done < "$DENY"

if [ "$FOUND" -gt 0 ]; then
  echo "leak-check: $FOUND hit(s). Remove or generalise them before committing."
  exit 1
fi
echo "leak-check: clean (${#FILES[@]} files, denylist $(grep -cvE '^(#|$)' "$DENY") patterns)"
