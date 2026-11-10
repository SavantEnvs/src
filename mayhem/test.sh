#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the OpenBSD mandoc(1) and libc regex regression suites (built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


MD="$SRC/mayhem/obj/normal/bin/mandoc"
RE="$SRC/mayhem/obj/normal/bin/re"
for b in "$MD" "$RE"; do
  [ -x "$b" ] || { echo "missing $b: mayhem/build.sh did not produce it" >&2; emit_ctrf "openbsd-mandoc-regex" 0 1; exit 1; }
done

pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- 1. mandoc golden-output regression suite (regress/usr.bin/mandoc/**) ----------------------
# Same invocations as regress/usr.bin/mandoc/Makefile.inc, run in the test's own directory.
# A .in file is compared byte-for-byte with its committed .out_<kind>.
R=regress/usr.bin/mandoc
suite() {
  local kind="$1" in out dir base
  while IFS= read -r out; do
    dir=$(dirname "$out"); base=$(basename "$out" ".out_$kind")
    [ -f "$dir/$base.in" ] || continue
    case "$kind" in
      ascii)    got=$(cd "$dir" && "$MD" -C /dev/null -mandoc -Ios=OpenBSD -Tascii "$base.in" 2>/dev/null; echo x) ;;
      markdown) got=$(cd "$dir" && "$MD" -C /dev/null -mandoc -Ios=OpenBSD -Tmarkdown "$base.in" 2>/dev/null; echo x) ;;
      lint)     got=$(cd "$dir" && "$MD" -C /dev/null -mandoc -Ios=OpenBSD -Tlint -Wall "$base.in" 2>&1 \
                      | sed -E 's/^mandoc: \/[^:]+\//mandoc: /' \
                      | grep -v 'referenced manual not found'; echo x) ;;
    esac
    want=$(cat "$out"; echo x)
    [ "$kind" = lint ] && want=$(grep -v 'referenced manual not found' "$out"; echo x)
    if [ "$got" = "$want" ]; then ok; else bad "mandoc $kind $dir/$base"; fi
  done < <(find "$R/mdoc" "$R/man" "$R/roff" "$R/tbl" "$R/eqn" "$R/char" -name "*.out_$kind" | LC_ALL=C sort)
}
suite ascii
suite markdown
suite lint
# eqn's html goldens use a different extraction in upstream's Makefile, so they are skipped.
while IFS= read -r out; do
  dir=$(dirname "$out"); base=$(basename "$out" .out_html)
  [ -f "$dir/$base.in" ] || continue
  got=$(cd "$dir" && "$MD" -C /dev/null -mandoc -Thtml "$base.in" 2>/dev/null \
        | sed -n '/BEGINTEST/,/ENDTEST/p' | sed '1d;$d'; echo x)
  if [ "$got" = "$(cat "$out"; echo x)" ]; then ok; else bad "mandoc html $dir/$base"; fi
done < <(find "$R/mdoc" "$R/man" "$R/roff" "$R/tbl" "$R/char" -name '*.out_html' | LC_ALL=C sort)

# --- 2. mandoc known-answer probes on a one-off page --------------------------------------------
kat=$(mktemp)
printf '.Dd January 1, 2020\n.Dt FOO 1\n.Os\n.Sh NAME\n.Nm foo\n.Nd frobnicate the bar\n.Sh DESCRIPTION\nThe\n.Nm\nutility does\n.Ar nothing .\n' > "$kat"
asc=$("$MD" -C /dev/null -Tascii -Ios=OpenBSD "$kat" 2>/dev/null | sed 's/.\x08//g')
echo "$asc" | grep -qxF 'FOO(1)                      General Commands Manual                     FOO(1)' && ok || bad "kat ascii header"
echo "$asc" | grep -qxF '     foo - frobnicate the bar' && ok || bad "kat ascii NAME line"
echo "$asc" | grep -qxF '     The foo utility does nothing.' && ok || bad "kat ascii body"
echo "$asc" | grep -qxF 'OpenBSD                         January 1, 2020                         FOO(1)' && ok || bad "kat ascii footer"
md=$("$MD" -C /dev/null -Tmarkdown -Ios=OpenBSD "$kat" 2>/dev/null)
[ "$md" = "$(printf 'FOO(1) - General Commands Manual\n\n# NAME\n\n**foo** - frobnicate the bar\n\n# DESCRIPTION\n\nThe\n**foo**\nutility does\n*nothing*.\n\nOpenBSD - January 1, 2020 - FOO(1)')" ] && ok || bad "kat markdown"
# the -Tlint mode must report a deliberately broken page
printf '.Dd January 1, 2020\n.Dt X 1\n.Os\n.Sh NAME\n.Nm x\n.Nd y\n.Bogus macro\n' > "$kat"
lint=$("$MD" -C /dev/null -Tlint -Wall "$kat" 2>&1)
case "$lint" in *'skipping unknown macro: .Bogus macro'*) ok ;; *) bad "kat lint unknown macro" ;; esac
: || bad "kat lint unknown macro"
rm -f "$kat"

# --- 3. libc regex regression suite (regress/lib/libc/regex/tests, driven by re) ---------------
T=regress/lib/libc/regex/tests
for mode in "" -el -er; do
  out=$("$RE" $mode < "$T" 2>&1); rc=$?
  if [ $rc -eq 0 ] && [ -z "$out" ]; then ok; else bad "regex suite mode '$mode' rc=$rc: $out"; fi
done
# per-line known-answer: expected match text and submatches are asserted by re itself, so a
# wrong expectation must be reported and make it exit non-zero.
re_expect_pass() { printf '%b' "$1" | "$RE" >/dev/null 2>&1; }
re_expect_fail() { out=$(printf '%b' "$1" | "$RE" 2>&1); rc=$?; [ $rc -ne 0 ] && echo "$out" | grep -q "$2"; }
re_expect_pass 'a(b+)c\tE\tabbbc\tabbbc\tbbb\n' && ok || bad "kat regex group"
re_expect_pass 'a\\(b*\\)c\tb\tac\tac\t@c\n' && ok || bad "kat regex bre empty group"
re_expect_fail 'a(b+)c\tE\tabbbc\tabbbc\tbb\n' 'instead' && ok || bad "kat regex wrong submatch must fail"
re_expect_fail 'abc\t-\tabd\tabc\n' 'REG_NOMATCH' && ok || bad "kat regex nomatch must fail"
re_expect_fail 'a(\tE\tx\tx\n' 'REG_EPAREN' && ok || bad "kat regex bad pattern must fail"

echo "mandoc/regex: passed=$pass failed=$fail"
emit_ctrf "openbsd-mandoc-regex" "$pass" "$fail" 0
