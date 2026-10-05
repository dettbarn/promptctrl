#!/usr/bin/env bash
# Test suite for deploy.sh.
# Isolation: every test runs a *copy* of deploy.sh inside a fresh mktemp sandbox,
# with cwd, HOME and all config paths inside that sandbox. deploy.sh resolves
# promptctrl.json, dev files and backup/ relative to cwd, so the real repo
# (dev files, backups, promptctrl.json) and real prod paths are never touched.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_SRC="$REPO_DIR/deploy.sh"

command -v jq > /dev/null || { echo "jq is required to run the tests"; exit 1; }

SANDBOX_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/promptctrl-test.XXXXXX")"
[[ "$SANDBOX_ROOT" == /*promptctrl-test.* && "$SANDBOX_ROOT" != "$REPO_DIR"* ]] || {
    echo "Refusing to run: unsafe sandbox $SANDBOX_ROOT"; exit 1; }

# Metadata-only snapshot (path, size, mtime) so no file content is read.
snapshot_repo() {
    find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o -path "$REPO_DIR/tests" -prune -o \
        -type f -printf '%p %s %T@\n' | sort
}
REPO_BEFORE="$(snapshot_repo)"

cleanup() {
    [[ "$SANDBOX_ROOT" == /*promptctrl-test.* ]] && rm -rf "$SANDBOX_ROOT"
}
trap cleanup EXIT

PASS=0
FAIL=0
CURRENT=""

# --- helpers -----------------------------------------------------------------

new_sandbox() { # sets $SB, copies the script, cd's into it
    SB="$(mktemp -d "$SANDBOX_ROOT/case.XXXXXX")"
    cp "$SCRIPT_SRC" "$SB/deploy.sh"
    mkdir -p "$SB/backup" "$SB/prod"
    cd "$SB" || exit 1
}

write_config() { # key dev prod [key dev prod ...]  (paths relative to $SB)
    local json='{}'
    while (($#)); do
        json=$(jq --arg k "$1" --arg d "$SB/$2" --arg p "$SB/$3" \
            '.[$k] = {dev: $d, prod: $p}' <<< "$json")
        shift 3
    done
    echo "$json" > "$SB/promptctrl.json"
}

run_deploy() { # args passed to deploy.sh; sets $OUT and $RC
    OUT="$(HOME="$SB" bash "$SB/deploy.sh" "$@" 2>&1)"
    RC=$?
}

backups() { find "$SB/backup" -type f ! -name .gitkeep | sort; }
backup_count() { backups | wc -l | tr -d ' '; }

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; [[ -n "${2:-}" ]] && echo "         $2"; }

assert_eq() { [[ "$1" == "$2" ]] && ok "$3" || bad "$3" "expected '$2', got '$1'"; }
assert_contains() { [[ "$1" == *"$2"* ]] && ok "$3" || bad "$3" "output lacks '$2': $1"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] && ok "$3" || bad "$3" "output unexpectedly has '$2'"; }
assert_file() { [[ "$(cat "$1")" == "$2" ]] && ok "$3" || bad "$3" "content of $1 was '$(cat "$1")'"; }

testcase() { CURRENT="$1"; echo "$1"; }

# --- tests -------------------------------------------------------------------

testcase "deploy: prod missing -> created from dev, no backup"
new_sandbox
echo "v1" > dev.md
write_config a dev.md prod/a.md
run_deploy
assert_eq "$RC" 0 "exit 0"
assert_file prod/a.md "v1" "prod created with dev content"
assert_contains "$OUT" "Deployed a" "reports deployment"
assert_eq "$(backup_count)" 0 "no backup created"
assert_file dev.md "v1" "dev unchanged"

testcase "deploy: identical -> skipped"
new_sandbox
echo "same" > dev.md; echo "same" > prod/a.md
write_config a dev.md prod/a.md
run_deploy
assert_eq "$RC" 0 "exit 0"
assert_contains "$OUT" "No changes for a" "reports no changes"
assert_eq "$(backup_count)" 0 "no backup created"
assert_file prod/a.md "same" "prod unchanged"

testcase "deploy: changed -> backup of old prod, prod updated"
new_sandbox
echo "new" > dev.md; echo "old" > prod/a.md
write_config a dev.md prod/a.md
run_deploy
assert_eq "$RC" 0 "exit 0"
assert_file prod/a.md "new" "prod updated"
assert_file dev.md "new" "dev unchanged"
assert_eq "$(backup_count)" 1 "exactly one backup"
b="$(backups)"
assert_file "$b" "old" "backup holds previous prod content"
[[ "$(basename "$b")" =~ ^a_a\.md\.backup\.[0-9]{8}_[0-9]{6}$ ]] \
    && ok "backup name is <key>_<prodfile>.backup.<timestamp>" \
    || bad "backup name format" "$(basename "$b")"
assert_contains "$OUT" "Changes detected for a" "reports changes"
assert_contains "$OUT" "Backup created:" "reports backup"

testcase "deploy: second run after deploy is a no-op"
new_sandbox
echo "new" > dev.md; echo "old" > prod/a.md
write_config a dev.md prod/a.md
run_deploy
run_deploy
assert_contains "$OUT" "No changes for a" "idempotent"
assert_eq "$(backup_count)" 1 "still one backup"

testcase "deploy: multiple keys handled independently"
new_sandbox
echo "d1" > d1.md; echo "d2" > d2.md; echo "d3" > d3.md
echo "p1-old" > prod/p1.md; echo "d2" > prod/p2.md
write_config one d1.md prod/p1.md two d2.md prod/p2.md three d3.md prod/p3.md
run_deploy
assert_file prod/p1.md "d1" "changed key deployed"
assert_file prod/p2.md "d2" "identical key untouched"
assert_file prod/p3.md "d3" "missing key created"
assert_eq "$(backup_count)" 1 "one backup (only for changed key)"

testcase "deploy: dev file missing -> skipped with warning"
new_sandbox
echo "old" > prod/a.md
write_config a missing.md prod/a.md
run_deploy
assert_eq "$RC" 0 "exit 0"
assert_contains "$OUT" "Dev file" "warns about dev file"
assert_file prod/a.md "old" "prod untouched"
assert_eq "$(backup_count)" 0 "no backup"

testcase "deploy: invalid dev/prod entries -> skipped with warning"
new_sandbox
echo "x" > dev.md
echo '{"nodev":{"prod":"'"$SB"'/prod/x.md"},"noprod":{"dev":"'"$SB"'/dev.md"},"emptyprod":{"dev":"'"$SB"'/dev.md","prod":""}}' > promptctrl.json
run_deploy
assert_eq "$RC" 0 "exit 0"
assert_contains "$OUT" "Invalid dev path for key nodev" "invalid dev warned"
assert_contains "$OUT" "Invalid prod path for key noprod" "missing prod warned"
assert_contains "$OUT" "Invalid prod path for key emptyprod" "empty prod warned"
assert_eq "$(ls prod | wc -l | tr -d ' ')" 0 "nothing deployed"

testcase "deploy: missing backup dir -> prod left unchanged"
new_sandbox
rm -rf backup
echo "new" > dev.md; echo "old" > prod/a.md
write_config a dev.md prod/a.md
run_deploy
[[ $RC -ne 0 ]] && ok "non-zero exit" || bad "non-zero exit" "rc=$RC"
assert_file prod/a.md "old" "prod not overwritten without backup"

testcase "config: missing promptctrl.json -> error"
new_sandbox
run_deploy
assert_eq "$RC" 1 "exit 1"
assert_contains "$OUT" "not found" "error message"

testcase "args: unknown argument -> usage, exit 1"
new_sandbox
write_config a dev.md prod/a.md
run_deploy --bogus
assert_eq "$RC" 1 "exit 1"
assert_contains "$OUT" "Usage:" "prints usage"

testcase "dry run: new prod would be created, nothing written"
new_sandbox
echo "v1" > dev.md
write_config a dev.md prod/a.md
run_deploy --dry-run
assert_eq "$RC" 0 "exit 0"
assert_contains "$OUT" "would be created at" "announces creation"
[[ ! -e prod/a.md ]] && ok "prod not created" || bad "prod not created"

testcase "dry run: identical -> no changes"
new_sandbox
echo "same" > dev.md; echo "same" > prod/a.md
write_config a dev.md prod/a.md
run_deploy -n
assert_contains "$OUT" "No changes for a" "reports no changes"

testcase "dry run: changed -> diff shown, no copy, no backup"
new_sandbox
echo "new" > dev.md; echo "old" > prod/a.md
write_config a dev.md prod/a.md
run_deploy --dry-run
assert_eq "$RC" 0 "exit 0"
assert_contains "$OUT" "Dry run: changes for a" "announces changes"
assert_contains "$OUT" "< new" "shows dev line"
assert_contains "$OUT" "> old" "shows prod line"
assert_file prod/a.md "old" "prod unchanged"
assert_file dev.md "new" "dev unchanged"
assert_eq "$(backup_count)" 0 "no backup created"

testcase "dry run: missing dev -> skipped with warning"
new_sandbox
write_config a missing.md prod/a.md
run_deploy -n
assert_contains "$OUT" "Dev file" "warns about dev file"

# --- final guard: real repo untouched ------------------------------------------

testcase "isolation: real repo (dev files, backups, config) unchanged"
cd "$REPO_DIR" || exit 1
assert_eq "$(snapshot_repo)" "$REPO_BEFORE" "no file in repo changed (path/size/mtime)"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
