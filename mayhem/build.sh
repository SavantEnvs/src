#!/usr/bin/env bash
#
# mayhem/build.sh — build the fuzz harnesses (sanitized, instrumented) and the functional-test
# programs (normal flags) for the userland pieces of OpenBSD src that we fuzz:
#   fuzz_mandoc  usr.bin/mandoc          (manual page parser + formatters)
#   fuzz_regex   lib/libc/regex          (POSIX regcomp/regexec, built as obsd_* so it
#                                         does not collide with glibc's regex)
# OpenBSD's own sources are compiled unmodified; mayhem/compat/ supplies the few libc
# functions glibc lacks (getprogname, strtonum, recallocarray, pledge/unveil stubs).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"
M=usr.bin/mandoc
R=lib/libc/regex
# "obj" is gitignored upstream (**/obj), so `git clean -ffdX` removes it.
OBJ="$SRC/mayhem/obj"
mkdir -p "$OBJ"
rm -rf "$OBJ/fuzz" "$OBJ/normal" "$OBJ/inc"
mkdir -p "$OBJ/fuzz/mandoc" "$OBJ/fuzz/regex" "$OBJ/fuzz/util" "$OBJ/normal/mandoc" "$OBJ/normal/regex" "$OBJ/normal/bin" "$OBJ/inc"

# OpenBSD's regex.h, under an include dir of its own so it never shadows glibc's.
cp include/regex.h "$OBJ/inc/regex.h"

# Fuzz flags: ASan+UBSan (halting), SanCov on the project code, DWARF 3.
# Relaxed UBSan checks (everything else stays halting):
#   function             mandoc and ohash call through differently-typed function pointers
#   signed-integer-overflow, shift-base, float-cast-overflow
#                        roff register arithmetic (roff.c) and the regex engine's state-set bit
#                        tricks (engine.c) and PostScript scaling (term_ps.c) overflow on hostile input within
#                        seconds and would halt every run before any coverage accrues.
FUZZ="$SANITIZER_FLAGS -fno-sanitize=function,signed-integer-overflow,shift-base,float-cast-overflow -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1"
COMPAT="-D_GNU_SOURCE -include $SRC/mayhem/compat/compat.h -w"
REGEX_RENAME="-Dregcomp=obsd_regcomp -Dregexec=obsd_regexec -Dregerror=obsd_regerror -Dregfree=obsd_regfree"

MANDOC_LIB_SRCS="mandoc_aux.c mandoc_ohash.c mandoc.c mandoc_msg.c mandoc_xr.c arch.c chars.c msec.c preconv.c read.c tag.c
 roff.c roff_escape.c roff_validate.c tbl.c tbl_opts.c tbl_layout.c tbl_data.c eqn.c
 mdoc.c mdoc_argv.c mdoc_macro.c mdoc_state.c mdoc_validate.c att.c st.c
 man_macro.c man.c man_validate.c out.c tree.c
 term.c term_ascii.c term_ps.c term_tab.c term_tag.c
 roff_term.c mdoc_term.c man_term.c eqn_term.c tbl_term.c mdoc_man.c
 html.c roff_html.c mdoc_html.c man_html.c eqn_html.c tbl_html.c mdoc_markdown.c"
MANDOC_CLI_SRCS="main.c dbm_map.c dbm.c dba_write.c dba_array.c dba.c dba_read.c manpath.c mandocdb.c mansearch.c"
UTIL_SRCS="lib/libutil/ohash.c lib/libc/stdlib/strtonum.c lib/libc/stdlib/recallocarray.c mayhem/compat/compat.c"
REGEX_SRCS="regcomp.c regexec.c regerror.c regfree.c"

# The fuzz build compiles mdoc_man.c and mdoc_markdown.c through mayhem/*_reset.c, which #include them
# unmodified and add a function that resets their file-scope state between inputs.
FUZZ_MANDOC_SRCS=$(for f in $MANDOC_LIB_SRCS; do case $f in
  mdoc_man.c) echo mayhem/mdoc_man_reset.c ;;
  mdoc_markdown.c) echo mayhem/mdoc_markdown_reset.c ;;
  *) echo $M/$f ;; esac; done)

# cc <outdir> <flags> <src>...   compiles each source to <outdir>/<basename>.o in parallel
cc_all() {
  local out="$1" flags="$2"; shift 2
  printf '%s\n' "$@" | xargs -P "$MAYHEM_JOBS" -I{} sh -c \
    "$CC -c $flags {} -o $out/\$(basename {} .c).o"
}

# ---- sanitized fuzz build ------------------------------------------------------------------
cc_all "$OBJ/fuzz/mandoc" "$FUZZ $COMPAT -I$SRC/lib/libutil -I$SRC/$M" $FUZZ_MANDOC_SRCS
cc_all "$OBJ/fuzz/util"   "$FUZZ $COMPAT -I$SRC/lib/libutil" $UTIL_SRCS
cc_all "$OBJ/fuzz/regex"  "$FUZZ $COMPAT $REGEX_RENAME -I$SRC/$R -I$OBJ/inc" $(for f in $REGEX_SRCS; do echo $R/$f; done)
$CC -c $SANITIZER_FLAGS $DEBUG_FLAGS mayhem/lsan_off.c -o "$OBJ/fuzz/lsan_off.o"
$CC -c $SANITIZER_FLAGS $DEBUG_FLAGS -x c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/fuzz/standalone_main.o"

H_MANDOC="$FUZZ $COMPAT -I$SRC/lib/libutil -I$SRC/$M"
H_REGEX="$FUZZ $COMPAT $REGEX_RENAME -I$OBJ/inc"
$CC -c $H_MANDOC mayhem/fuzz_mandoc.c -o "$OBJ/fuzz/fuzz_mandoc.o"
$CC -c $H_REGEX  mayhem/fuzz_regex.c  -o "$OBJ/fuzz/fuzz_regex.o"

LINK="$SANITIZER_FLAGS $DEBUG_FLAGS"
$CC $LINK $LIB_FUZZING_ENGINE "$OBJ/fuzz/fuzz_mandoc.o" "$OBJ"/fuzz/mandoc/*.o "$OBJ"/fuzz/util/*.o "$OBJ/fuzz/lsan_off.o" -lz -o "$SRC/fuzz_mandoc"
$CC $LINK "$OBJ/fuzz/standalone_main.o" "$OBJ/fuzz/fuzz_mandoc.o" "$OBJ"/fuzz/mandoc/*.o "$OBJ"/fuzz/util/*.o "$OBJ/fuzz/lsan_off.o" -lz -o "$SRC/fuzz_mandoc-standalone"
$CC $LINK $LIB_FUZZING_ENGINE "$OBJ/fuzz/fuzz_regex.o" "$OBJ"/fuzz/regex/*.o "$OBJ/fuzz/lsan_off.o" -o "$SRC/fuzz_regex"
$CC $LINK "$OBJ/fuzz/standalone_main.o" "$OBJ/fuzz/fuzz_regex.o" "$OBJ"/fuzz/regex/*.o "$OBJ/fuzz/lsan_off.o" -o "$SRC/fuzz_regex-standalone"

# ---- normal-flags test programs (test.sh only runs them) ------------------------------------
NORM="-O2 $COVERAGE_FLAGS"
cc_all "$OBJ/normal/mandoc" "$NORM $COMPAT -I$SRC/lib/libutil -I$SRC/$M" \
  $(for f in $MANDOC_LIB_SRCS $MANDOC_CLI_SRCS; do echo $M/$f; done) $UTIL_SRCS
$CC $NORM $COVERAGE_FLAGS "$OBJ"/normal/mandoc/*.o -lz -o "$OBJ/normal/bin/mandoc"

RE_DIR=regress/lib/libc/regex
cc_all "$OBJ/normal/regex" "$NORM $COMPAT $REGEX_RENAME -DREDEBUG -DPOSIX_MISTAKE -I$SRC/$R -I$OBJ/inc" \
  $(for f in $REGEX_SRCS; do echo $R/$f; done) $RE_DIR/main.c $RE_DIR/split.c $RE_DIR/debug.c
$CC $NORM $COVERAGE_FLAGS "$OBJ"/normal/regex/*.o -o "$OBJ/normal/bin/re"
