#!/usr/bin/env bash
#
# Usage:
#   test/spec.sh <function name>

set -o nounset
set -o pipefail
set -o errexit
shopt -s strict:all 2>/dev/null || true  # dogfood for OSH

REPO_ROOT=$(cd "$(dirname $0)/.."; pwd)

source test/common.sh
source test/spec-common.sh
source devtools/run-task.sh

if test -z "${IN_NIX_SHELL:-}"; then
  source build/dev-shell.sh  # to run 'dash', etc.
fi

# TODO: Just use 'dash bash' and $PATH
readonly DASH=dash
readonly BASH=bash
readonly MKSH=mksh
readonly ZSH=zsh
readonly BUSYBOX_ASH=ash

# ash and dash are similar, so not including ash by default.  zsh is not quite
# POSIX.
readonly REF_SHELLS=($DASH $BASH $MKSH)

# TODO: Could be
# test/sh_spec.py --osh-sanity-check --oils-bin-dir 
# Along with comparison shells

check-survey-shells() {
  ### Make sure bash, zsh, OSH, etc. exist

  # Note: yash isn't here, but it is used in a couple tests

  test/spec-runner.sh shell-sanity-check "${REF_SHELLS[@]}" $ZSH $BUSYBOX_ASH $OSH_LIST
}

# TODO: remove this stub after we hollow out this file

run-file() { test/spec-py.sh run-file "$@"; }

#
# Misc
#

# Really what I want is enter(func) and exit(func), and filter by regex?
trace-var-sub() {
  local out=_tmp/coverage
  mkdir -p $out

  # This creates *.cover files, with line counts.
  #python -m trace --count -C $out \

  # This prints trace with line numbers to stdout.
  #python -m trace --trace -C $out \
  PYTHONPATH=. python -m trace --trackcalls -C $out \
    test/sh_spec.py spec/var-sub.test.sh $DASH $BASH "$@"

  ls -l $out
  head $out/*.cover
}

#
# Individual tests.
#
# We configure the shells they run on and the number of allowed failures (to
# prevent regressions.)
#

interactive-parse() {
  run-file interactive-parse "$@"
}

smoke() {
  run-file smoke "$@"
}

interactive() {
  run-file interactive "$@"
}

prompt() {
  run-file prompt "$@"
}

osh-only() {
  run-file osh-only "$@"
}

bugs() {
  run-file bugs "$@"
}

TODO-deprecate() {
  run-file TODO-deprecate "$@"
}

blog1() {
  sh-spec spec/blog1.test.sh \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

blog2() {
  sh-spec spec/blog2.test.sh \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

blog-other1() {
  sh-spec spec/blog-other1.test.sh \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

alias() {
  run-file alias "$@"
}

comments() {
  sh-spec spec/comments.test.sh ${REF_SHELLS[@]} $OSH_LIST "$@"
}

word-split() {
  run-file word-split "$@"
}

word-eval() {
  sh-spec spec/word-eval.test.sh \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

# These cases apply to many shells.
assign() {
  sh-spec spec/assign.test.sh --oils-failures-allowed 2 \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@" 
}

# These cases apply to a few shells.
assign-extended() {
  sh-spec spec/assign-extended.test.sh \
    $BASH $MKSH $OSH_LIST "$@" 
}

# Corner cases that OSH doesn't handle
assign-deferred() {
  sh-spec spec/assign-deferred.test.sh \
    $BASH $MKSH "$@" 
}

# These test associative arrays
assign-dialects() {
  sh-spec spec/assign-dialects.test.sh --oils-failures-allowed 1 \
    $BASH $MKSH $OSH_LIST "$@" 
}

background() {
  sh-spec spec/background.test.sh --oils-failures-allowed 2 \
    ${REF_SHELLS[@]} $OSH_LIST "$@" 
}

subshell() {
  sh-spec spec/subshell.test.sh \
    ${REF_SHELLS[@]} $OSH_LIST "$@" 
}

quote() {
  sh-spec spec/quote.test.sh \
    ${REF_SHELLS[@]} $BUSYBOX_ASH $OSH_LIST "$@"
}

loop() {
  sh-spec spec/loop.test.sh \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

case_() {
  run-file case_ "$@"
}

if_() {
  sh-spec spec/if_.test.sh \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

builtins() {
  sh-spec spec/builtins.test.sh --oils-failures-allowed 2 \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

builtin-eval-source() {
  sh-spec spec/builtin-eval-source.test.sh \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

builtin-io() {
  sh-spec spec/builtin-io.test.sh --oils-failures-allowed 3 \
    ${REF_SHELLS[@]} $ZSH $BUSYBOX_ASH $OSH_LIST "$@"
}

nul-bytes() {
  sh-spec spec/nul-bytes.test.sh --oils-failures-allowed 2 \
    ${REF_SHELLS[@]} $ZSH $BUSYBOX_ASH $OSH_LIST "$@"
}

# Special bash printf things like -v and %q.  Portable stuff goes in builtin-io.
builtin-printf() {
  sh-spec spec/builtin-printf.test.sh --oils-failures-allowed 1 \
    ${REF_SHELLS[@]} $ZSH $BUSYBOX_ASH $OSH_LIST "$@"
}

builtins2() {
  sh-spec spec/builtins2.test.sh \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

builtin-history() {
  run-file builtin-history "$@"
}

# dash and mksh don't implement 'dirs'
builtin-dirs() {
  sh-spec spec/builtin-dirs.test.sh \
    $BASH $ZSH $OSH_LIST "$@"
}

builtin-vars() {
  sh-spec spec/builtin-vars.test.sh --oils-failures-allowed 1 \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

builtin-getopts() {
  sh-spec spec/builtin-getopts.test.sh --oils-failures-allowed 0 \
    ${REF_SHELLS[@]} $BUSYBOX_ASH $OSH_LIST "$@"
}

builtin-bracket() {
  sh-spec spec/builtin-bracket.test.sh \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

builtin-trap() {
  sh-spec spec/builtin-trap.test.sh --oils-failures-allowed 0 \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

builtin-trap-bash() {
  sh-spec spec/builtin-trap-bash.test.sh --oils-failures-allowed 1 \
    $BASH $OSH_LIST "$@"
}

# Bash implements type -t, but no other shell does.  For Nix.
# zsh/mksh/dash don't have the 'help' builtin.
builtin-bash() {
  sh-spec spec/builtin-bash.test.sh --oils-failures-allowed 4 \
    $BASH $OSH_LIST "$@"
}

vars-bash() {
  sh-spec spec/vars-bash.test.sh --oils-failures-allowed 1 \
    $BASH $OSH_LIST "$@"
}

vars-special() {
  sh-spec spec/vars-special.test.sh --oils-failures-allowed 2 \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

# This is bash/OSH only
builtin-completion() {
  sh-spec spec/builtin-completion.test.sh --oils-failures-allowed 1 \
    $BASH $OSH_LIST "$@"
}

builtin-special() {
  sh-spec spec/builtin-special.test.sh --oils-failures-allowed 4 \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

builtin-times() {
  sh-spec spec/builtin-times.test.sh $BASH $ZSH $OSH_LIST "$@"
}

command-parsing() {
  sh-spec spec/command-parsing.test.sh ${REF_SHELLS[@]} $OSH_LIST "$@"
}

func-parsing() {
  sh-spec spec/func-parsing.test.sh ${REF_SHELLS[@]} $OSH_LIST "$@"
}

sh-func() {
  sh-spec spec/sh-func.test.sh --oils-failures-allowed 1 \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

glob() {
  # Note: can't pass because it assumes 'bin' exists, etc.
  sh-spec spec/glob.test.sh --oils-failures-allowed 4 \
    ${REF_SHELLS[@]} $BUSYBOX_ASH $OSH_LIST "$@"
}

arith() {
  sh-spec spec/arith.test.sh --oils-failures-allowed 0 \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

command-sub() {
  sh-spec spec/command-sub.test.sh \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

command_() {
  sh-spec spec/command_.test.sh \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

pipeline() {
  sh-spec spec/pipeline.test.sh \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

explore-parsing() {
  sh-spec spec/explore-parsing.test.sh \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

parse-errors() {
  sh-spec spec/parse-errors.test.sh --oils-failures-allowed 3 \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

here-doc() {
  # NOTE: The last two tests, 31 and 32, have different behavior on my Ubuntu
  # and Debian machines.
  # - On Ubuntu, read_from_fd.py fails with Errno 9 -- bad file descriptor.
  # - On Debian, the whole process hangs.
  # Is this due to Python 3.2 vs 3.4?  Either way osh doesn't implement the
  # functionality, so it's probably best to just implement it.
  sh-spec spec/here-doc.test.sh --range 0-31 \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

redirect() {
  sh-spec spec/redirect.test.sh --oils-failures-allowed 2 \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

posix() {
  sh-spec spec/posix.test.sh \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

introspect() {
  sh-spec spec/introspect.test.sh --oils-failures-allowed 0 \
    $BASH $OSH_LIST "$@"
}

tilde() {
  sh-spec spec/tilde.test.sh --oils-failures-allowed 0 \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

var-op-test() {
  sh-spec spec/var-op-test.test.sh --oils-failures-allowed 0 \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

var-op-len() {
  sh-spec spec/var-op-len.test.sh \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

var-op-patsub() {
  # 1 unicode failure, and [^]] which is a parsing divergence
  sh-spec spec/var-op-patsub.test.sh --oils-failures-allowed 2 \
    $BASH $MKSH $ZSH $OSH_LIST "$@"
  # TODO: can add $BUSYBOX_ASH
}

var-op-slice() {
  # dash doesn't support any of these operations
  sh-spec spec/var-op-slice.test.sh --oils-failures-allowed 1 \
    $BASH $MKSH $ZSH $OSH_LIST "$@"
}

var-op-bash() {
  sh-spec spec/var-op-bash.test.sh --oils-failures-allowed 5 \
    $BASH $OSH_LIST "$@"
}

var-op-strip() {
  sh-spec spec/var-op-strip.test.sh --oils-failures-allowed 0 \
    ${REF_SHELLS[@]} $ZSH $BUSYBOX_ASH $OSH_LIST "$@"
}

var-sub() {
  # NOTE: ZSH has interesting behavior, like echo hi > "$@" can write to TWO
  # FILES!  But ultimately we don't really care, so I disabled it.
  sh-spec spec/var-sub.test.sh \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

var-num() {
  run-file var-num "$@"
}

var-sub-quote() {
  sh-spec spec/var-sub-quote.test.sh --oils-failures-allowed 0 \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

sh-usage() {
  run-file sh-usage "$@"
}

sh-options() {
  run-file sh-options "$@"
}

xtrace() {
  sh-spec spec/xtrace.test.sh --oils-failures-allowed 1 \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

strict-options() {
  sh-spec spec/strict-options.test.sh \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

exit-status() {
  sh-spec spec/exit-status.test.sh --oils-failures-allowed 1 \
    ${REF_SHELLS[@]} $OSH_LIST "$@"
}

errexit() {
  sh-spec spec/errexit.test.sh --oils-failures-allowed 0 \
    ${REF_SHELLS[@]} $BUSYBOX_ASH $OSH_LIST "$@"
}

errexit-osh() {
  run-file errexit-osh "$@"
}

fatal-errors() {
  sh-spec spec/fatal-errors.test.sh --oils-failures-allowed 0 \
    ${REF_SHELLS[@]} $ZSH $OSH_LIST "$@"
}

# 
# Non-POSIX extensions: arrays, brace expansion, [[, ((, etc.
#

# There as many non-POSIX arithmetic contexts.
arith-context() {
  sh-spec spec/arith-context.test.sh \
    $BASH $MKSH $ZSH $OSH_LIST "$@"
}

array() {
  sh-spec spec/array.test.sh \
    $BASH $MKSH $OSH_LIST "$@"
}

array-compat() {
  run-file array-compat "$@"
}

type-compat() {
  sh-spec spec/type-compat.test.sh $BASH $OSH_LIST "$@"
}

# += is not POSIX and not in dash.
append() {
  run-file append "$@"
}

# associative array -- mksh and zsh implement different associative arrays.
assoc() {
  sh-spec spec/assoc.test.sh --oils-failures-allowed 3 \
    $BASH $OSH_LIST "$@"
}

# ZSH also has associative arrays
assoc-zsh() {
  sh-spec spec/assoc-zsh.test.sh $ZSH "$@"
}

# NOTE: zsh passes about half and fails about half.  It supports a subset of [[
# I guess.
dbracket() {
  sh-spec spec/dbracket.test.sh --oils-failures-allowed 0 \
    $BASH $MKSH $OSH_LIST "$@"
  #sh-spec spec/dbracket.test.sh $BASH $MKSH $OSH_LIST $ZSH "$@"
}

dparen() {
  sh-spec spec/dparen.test.sh --oils-failures-allowed 1 \
    $BASH $MKSH $ZSH $OSH_LIST "$@"
}

brace-expansion() {
  sh-spec spec/brace-expansion.test.sh \
    $BASH $MKSH $ZSH $OSH_LIST "$@"
}

regex() {
  sh-spec spec/regex.test.sh --oils-failures-allowed 2 \
    $BASH $ZSH $OSH_LIST "$@"
}

process-sub() {
  # mksh and dash don't support it
  sh-spec spec/process-sub.test.sh --oils-failures-allowed 0 \
    $BASH $ZSH $OSH_LIST "$@"
}

# This does file system globbing
extglob-files() {
  sh-spec spec/extglob-files.test.sh --oils-failures-allowed 1 \
    $BASH $MKSH $OSH_LIST "$@"
}

# This does string matching.
extglob-match() {
  sh-spec spec/extglob-match.test.sh --oils-failures-allowed 0 \
    $BASH $MKSH $OSH_LIST "$@"
}

nocasematch-match() {
  sh-spec spec/nocasematch-match.test.sh --oils-failures-allowed 3 \
    $BASH $OSH_LIST "$@"
}

# ${!var} syntax -- oil should replace this with associative arrays.
# mksh has completely different behavior for this syntax.  Not worth testing.
var-ref() {
  sh-spec spec/var-ref.test.sh --oils-failures-allowed 0 \
    $BASH $OSH_LIST "$@"
}

# declare / local -n
# there is one divergence when combining -n and ${!ref}
nameref() {
  sh-spec spec/nameref.test.sh --oils-failures-allowed 7 \
    $BASH $MKSH $OSH_LIST "$@"
}

let() {
  sh-spec spec/let.test.sh $BASH $MKSH $ZSH "$@"
}

for-expr() {
  sh-spec spec/for-expr.test.sh \
    $BASH $ZSH $OSH_LIST "$@"
}

empty-bodies() {
  sh-spec spec/empty-bodies.test.sh "${REF_SHELLS[@]}" $ZSH $OSH_LIST "$@"
}

# TODO: This is for the ANTLR grammars, in the oil-sketch repo.
# osh has infinite loop?
shell-grammar() {
  sh-spec spec/shell-grammar.test.sh $BASH $MKSH $ZSH "$@"
}

serialize() {
  # dash doesn't have echo -e, $'', etc.
  sh-spec spec/serialize.test.sh --oils-failures-allowed 0 \
    $BASH $MKSH $ZSH $BUSYBOX_ASH $OSH_LIST "$@"
}

#
# Smoosh
#

readonly SMOOSH_REPO=~/git/languages/smoosh

sh-spec-smoosh-env() {
  local test_file=$1
  shift

  # - smoosh tests use $TEST_SHELL instead of $SH
  # - cd $TMP to avoid littering repo
  # - pass -o posix
  # - timeout of 1 second
  # - Some tests in smoosh use $HOME and $LOGNAME

  sh-spec $test_file \
    --sh-env-var-name TEST_SHELL \
    --posix \
    --env-pair "TEST_UTIL=$SMOOSH_REPO/tests/util" \
    --env-pair "LOGNAME=$LOGNAME" \
    --env-pair "HOME=$HOME" \
    --timeout 1 \
    --oils-bin-dir $REPO_ROOT/bin \
    --compare-shells \
    "$@"
}

# For speed, only run with one copy of OSH.
readonly smoosh_osh_list=$OSH_CPYTHON

smoosh() {
  ### Run case smoosh from the console

  # TODO: Use --oils-bin-dir
  # our_shells, etc.

  sh-spec-smoosh-env _tmp/smoosh.test.sh \
    ${REF_SHELLS[@]} $smoosh_osh_list \
    "$@"
}

smoosh-hang() {
  ### Run case smoosh-hang from the console

  # Need the smoosh timeout tool to run correctly.
  sh-spec-smoosh-env _tmp/smoosh-hang.test.sh \
    --timeout-bin "$SMOOSH_REPO/tests/util/timeout" \
    --timeout 1 \
    "$@"
}

_one-html() {
  local spec_name=$1
  shift

  # TODO:
  # - Smooth tests be in _tmp/spec/smoosh ?
  # - They could go in the CI

  local base_dir=_tmp/spec/smoosh
  mkdir -p $base_dir

  test/spec-runner.sh _test-to-html _tmp/${spec_name}.test.sh \
    > $base_dir/${spec_name}.test.html

  local out=$base_dir/${spec_name}.html
  set +o errexit
  # Shell function is smoosh or smoosh-hang
  time $spec_name --format html "$@" > $out
  set -o errexit

  echo
  echo "Wrote $out"

  # NOTE: This IGNORES the exit status.
}

smoosh-html() {
  _one-html smoosh "$@"
}

smoosh-hang-html() {
  _one-html smoosh-hang "$@"
}

html-demo() {
  ### Test for --format html

  local out=_tmp/spec/demo.html
  builtin-special --format html "$@" > $out

  echo
  echo "Wrote $out"
}

#
# Hay is part of the Oil suite
#

hay() {
  sh-spec spec/hay.test.sh --oils-failures-allowed 2 \
    $OSH_LIST "$@"
}

hay-isolation() {
  sh-spec spec/hay-isolation.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

hay-meta() {
  sh-spec spec/hay-meta.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

#
# Oil Language
#

ysh-usage() {
  run-file ysh-usage "$@"
}

ysh-unicode() {
  run-file ysh-unicode "$@"
}

ysh-bin() {
  run-file ysh-bin "$@"
}

ysh-array() {
  run-file ysh-array "$@"
}

ysh-assign() {
  run-file ysh-assign "$@"
}

ysh-blocks() {
  sh-spec spec/ysh-blocks.test.sh --oils-failures-allowed 4 \
    $OSH_LIST "$@"
}

ysh-bugs() {
  run-file ysh-bugs "$@"
}

ysh-builtins() {
  run-file ysh-builtins "$@"
}

ysh-builtin-argparse() {
  run-file ysh-builtin-argparse "$@"
}

ysh-builtin-describe() {
  run-file ysh-builtin-describe "$@"
}

# Related to errexit-oil
ysh-builtin-error() {
  sh-spec spec/ysh-builtin-error.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

ysh-builtin-pp() {
  sh-spec spec/ysh-builtin-pp.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

ysh-builtin-process() {
  sh-spec spec/ysh-builtin-process.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

ysh-builtin-shopt() {
  sh-spec spec/ysh-builtin-shopt.test.sh --oils-failures-allowed 1 \
    $OSH_LIST "$@"
}

ysh-case() {
  run-file ysh-case "$@"
}

ysh-command-sub() {
  sh-spec spec/ysh-command-sub.test.sh \
    $OSH_LIST "$@"
}

ysh-demo() {
  # Using OSH for minimalism
  sh-spec spec/ysh-demo.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

ysh-expr() {
  sh-spec spec/ysh-expr.test.sh --oils-failures-allowed 1 \
    $OSH_LIST "$@"
}

ysh-expr-bool() {
  run-file ysh-expr-bool "$@"
}

ysh-expr-arith() {
  sh-spec spec/ysh-expr-arith.test.sh --oils-failures-allowed 2 \
    $OSH_LIST "$@"
}

ysh-expr-compare() {
  sh-spec spec/ysh-expr-compare.test.sh --oils-failures-allowed 2 \
    $OSH_LIST "$@"
}

ysh-expr-sub() {
  run-file ysh-expr-sub "$@"
}

ysh-for() {
  run-file ysh-for "$@"
}

ysh-methods() {
  run-file ysh-methods "$@"
}

ysh-funcs() {
  run-file ysh-funcs "$@"
}

ysh-funcs-builtin() {
  run-file ysh-funcs-builtin "$@"
}

ysh-funcs-external() {
  run-file ysh-funcs-external "$@"
}

ysh-interactive() {
  run-file ysh-interactive "$@"
}

ysh-json() {
  run-file ysh-json "$@"
}

ysh-keywords() {
  run-file ysh-keywords "$@"
}

ysh-multiline() {
  sh-spec spec/ysh-multiline.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

ysh-options() {
  sh-spec spec/ysh-options.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

ysh-options-assign() {
  sh-spec spec/ysh-options-assign.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

ysh-proc() {
  sh-spec spec/ysh-proc.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

ysh-regex() {
  sh-spec spec/ysh-regex.test.sh --oils-failures-allowed 4 \
    $OSH_LIST "$@"
}

ysh-reserved() {
  run-file ysh-reserved "$@"
}

ysh-scope() {
  sh-spec spec/ysh-scope.test.sh --oils-failures-allowed 1 \
    $OSH_LIST "$@"
}

ysh-slice-range() {
  sh-spec spec/ysh-slice-range.test.sh --oils-failures-allowed 5 \
    $OSH_LIST "$@"
}

ysh-string() {
  run-file ysh-string "$@"
}

ysh-special-vars() {
  run-file ysh-special-vars "$@"
}

ysh-tuple() {
  run-file ysh-tuple "$@"
}

ysh-var-sub() {
  sh-spec spec/ysh-var-sub.test.sh --oils-failures-allowed 4 \
    $OSH_LIST "$@"
}

ysh-with-sh() {
  run-file ysh-with-sh "$@"
}

ysh-word-eval() {
  sh-spec spec/ysh-word-eval.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

ysh-xtrace() {
  sh-spec spec/ysh-xtrace.test.sh --oils-failures-allowed 0 \
    $OSH_LIST "$@"
}

ysh-user-feedback() {
  run-file ysh-user-feedback "$@"
}

ysh-builtin-error() {
  run-file ysh-builtin-error "$@"
}

#
# More OSH
#

nix-idioms() {
  sh-spec spec/nix-idioms.test.sh --oils-failures-allowed 2 \
    $BASH $OSH_LIST "$@"
}

ble-idioms() {
  sh-spec spec/ble-idioms.test.sh --oils-failures-allowed 0 \
    $BASH $ZSH $MKSH $BUSYBOX_ASH $OSH_LIST "$@"
}

ble-features() {
  sh-spec spec/ble-features.test.sh --oils-failures-allowed 0 \
    $BASH $ZSH $MKSH $BUSYBOX_ASH $DASH yash $OSH_LIST "$@"
}

toysh() {
  sh-spec spec/toysh.test.sh --oils-failures-allowed 3 \
    $BASH $MKSH $OSH_LIST "$@"
}

toysh-posix() {
  sh-spec spec/toysh-posix.test.sh --oils-failures-allowed 3 \
    ${REF_SHELLS[@]} $ZSH yash $OSH_LIST "$@"
}

#
# Tea Language
#

tea-func() {
  # all of these were broken by the new grammar!
  sh-spec spec/tea-func.test.sh --oils-failures-allowed 15 \
    $OSH_LIST "$@"
}

run-task "$@"
