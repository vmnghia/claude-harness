#!/usr/bin/env bash
# install.sh [--update | --doctor] <target-repo>
#
# Installs the harness core into <target-repo>/.claude/ by copying, so every relative link
# (agents → ../rules/…) keeps working and Claude Code discovers it natively.
#
#   (no flag)  first install. Refuses to overwrite any existing file it didn't install; merges
#              hook registrations into an existing .claude/settings.json; seeds .claude/project.md
#              from project-template/ only if absent.
#   --update   re-copies core. A file whose hash still matches the manifest (nobody edited it) is
#              replaced; an edited file is kept, and the new version is written next to it as
#              <file>.harness-new for you to merge.
#   --doctor   reports edited, missing and outdated files against the manifest and this core, then
#              runs the installed harness-check.
#
# The manifest, .claude/.harness-manifest, records the core version and one "<sha256>  <path>"
# line per installed file. Needs: bash, git, node ≥18, sha256sum.

set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
CORE="$SRC/core"
MODE=install
case "${1:-}" in --update) MODE=update; shift;; --doctor) MODE=doctor; shift;; -h|--help) sed -n 2,19p "$0"; exit 0;; esac
[ $# -eq 1 ] || { echo "usage: install.sh [--update | --doctor] <target-repo>" >&2; exit 64; }
TARGET="$(cd "$1" && pwd)"
DEST="$TARGET/.claude"
MAN="$DEST/.harness-manifest"
git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "install: $TARGET is not a git repo" >&2; exit 2; }
VERSION="$(git -C "$SRC" describe --always --dirty 2>/dev/null || echo uncommitted)"

hash() { sha256sum "$1" | cut -d' ' -f1; }
core_files() { (cd "$CORE" && find . -type f ! -name settings.json | sed 's|^\./||' | sort); }
man_hash() { [ -f "$MAN" ] && awk -v p="$1" '$2==p {print $1}' "$MAN"; }

merge_settings() { # merge core hook registrations into DEST/settings.json, skipping duplicates
  node -e '
    const fs=require("fs"), [core,dest]=process.argv.slice(1);
    const c=JSON.parse(fs.readFileSync(core,"utf8"));
    const d=fs.existsSync(dest)?JSON.parse(fs.readFileSync(dest,"utf8")):{};
    d.hooks=d.hooks||{}; let added=0;
    for (const [ev,groups] of Object.entries(c.hooks||{})) {
      d.hooks[ev]=d.hooks[ev]||[];
      for (const g of groups) {
        let t=d.hooks[ev].find(x=>(x.matcher||"")===(g.matcher||""));
        if (!t) { t={...(g.matcher?{matcher:g.matcher}:{}),hooks:[]}; d.hooks[ev].push(t); }
        for (const h of g.hooks) if (!t.hooks.some(x=>x.command===h.command)) { t.hooks.push(h); added++; }
      }
    }
    fs.writeFileSync(dest, JSON.stringify(d,null,2)+"\n");
    console.log("  settings.json: "+added+" hook registration(s) added");' "$CORE/settings.json" "$DEST/settings.json"
}

write_manifest() { # write_manifest <file listing "<hash>  <path>" lines>
  { echo "# claude-code-harness manifest — do not edit"; echo "version $VERSION"; cat "$1"; } > "$MAN"
}

case "$MODE" in
install)
  [ -f "$MAN" ] && { echo "install: already installed ($MAN). Use --update." >&2; exit 2; }
  CONFLICTS=$(core_files | while read -r f; do [ -e "$DEST/$f" ] && echo "$f"; done || true)
  if [ -n "$CONFLICTS" ]; then
    echo "install: these files already exist in $DEST and would be overwritten:" >&2
    echo "$CONFLICTS" | sed 's/^/  /' >&2
    echo "Move them aside (or merge them after installing), then re-run." >&2
    exit 2
  fi
  mkdir -p "$DEST"; TMP=$(mktemp)
  core_files | while read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"; cp -p "$CORE/$f" "$DEST/$f"; echo "$(hash "$DEST/$f")  $f" >> "$TMP"
  done
  merge_settings
  if [ -e "$DEST/project.md" ]; then echo "  project.md: kept existing"
  else cp "$SRC/project-template/project.md" "$DEST/project.md"; echo "  project.md: seeded from template, fill in the TODOs"; fi
  write_manifest "$TMP"; rm -f "$TMP"
  echo "installed $(core_files | wc -l) files, version $VERSION, into $DEST"
  echo "next: fill in $DEST/project.md, then run: bash $DEST/scripts/harness-check.sh"
  ;;
update)
  [ -f "$MAN" ] || { echo "update: no manifest at $MAN. Run a plain install first." >&2; exit 2; }
  TMP=$(mktemp); NEW=0; UPD=0; KEPT=0
  while read -r f; do
    if [ ! -e "$DEST/$f" ]; then
      mkdir -p "$DEST/$(dirname "$f")"; cp -p "$CORE/$f" "$DEST/$f"; NEW=$((NEW+1))
    elif [ "$(hash "$DEST/$f")" = "$(hash "$CORE/$f")" ]; then :
    elif [ "$(hash "$DEST/$f")" = "$(man_hash "$f")" ]; then
      cp -p "$CORE/$f" "$DEST/$f"; UPD=$((UPD+1))
    else
      cp -p "$CORE/$f" "$DEST/$f.harness-new"; KEPT=$((KEPT+1)); echo "  edited locally, kept: $f (new version: $f.harness-new)"
      echo "$(man_hash "$f")  $f" >> "$TMP"; continue
    fi
    echo "$(hash "$DEST/$f")  $f" >> "$TMP"
  done < <(core_files)
  awk 'NR>2 {print $2}' "$MAN" | while read -r f; do
    [ -e "$CORE/$f" ] || echo "  no longer in core (left in place, delete if unused): $f"
  done
  merge_settings
  write_manifest "$TMP"; rm -f "$TMP"
  echo "update to $VERSION: $NEW new, $UPD replaced, $KEPT kept with .harness-new"
  ;;
doctor)
  [ -f "$MAN" ] || { echo "doctor: not installed (no $MAN)" >&2; exit 2; }
  echo "installed: $(sed -n 's/^version //p' "$MAN") · this core: $VERSION"
  ISSUES=0
  while read -r h f; do
    if [ ! -e "$DEST/$f" ]; then echo "  missing: $f"; ISSUES=$((ISSUES+1))
    elif [ "$(hash "$DEST/$f")" != "$h" ]; then echo "  edited locally: $f"; ISSUES=$((ISSUES+1)); fi
    if [ -e "$CORE/$f" ] && [ "$h" != "$(hash "$CORE/$f")" ]; then echo "  outdated (core changed): $f"; fi
  done < <(awk 'NR>2' "$MAN")
  core_files | while read -r f; do man_hash "$f" | grep -q . || echo "  new in core, not installed: $f"; done
  find "$DEST" -name '*.harness-new' | sed "s|$DEST/|  unmerged update: |"
  [ "$ISSUES" -eq 0 ] && echo "  manifest: all installed files match"
  echo "--- harness-check:"
  (cd "$TARGET" && CLAUDE_PROJECT_DIR="$TARGET" bash "$DEST/scripts/harness-check.sh" | tail -3)
  ;;
esac
