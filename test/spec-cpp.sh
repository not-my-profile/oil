#!/usr/bin/env bash
#
# Test the C++ translation of Oil.
#
# Usage:
#   test/spec-cpp.sh <function name>
#
# Examples:
#   test/spec-cpp.sh run-file smoke -r 0 -v
#   NUM_SPEC_TASKS=2 test/spec-cpp.sh osh-all

set -o nounset
set -o pipefail
set -o errexit

source test/common.sh  # html-head
source test/spec-common.sh
source web/table/html.sh

shopt -s failglob  # to debug TSV expansion failure below

REPO_ROOT=$(cd $(dirname $0)/.. && pwd)
readonly REPO_ROOT

# Run with ASAN binary by default
OSH_CC=${OSH_CC:-$REPO_ROOT/_bin/cxx-asan/osh}

# Same variable in test/spec-runner.sh
NUM_SPEC_TASKS=${NUM_SPEC_TASKS:-400}

readonly -a COMPARE_CPP_SHELLS=(
    $REPO_ROOT/bin/osh
    $OSH_CC
)

# TODO: Use OIL_GC_ON_EXIT=1 instead
export ASAN_OPTIONS='detect_leaks=0'

#
# For translation
#

asan-smoke() {
  ninja _bin/cxx-asan/osh
  _bin/cxx-asan/osh -c 'echo -c'
  echo 'echo stdin' | _bin/cxx-asan/osh
}

run-file() {
  ### Run a test with the given name.

  local test_name=$1
  shift

  local spec_subdir='cpp'  # matches $spec_subdir in all-parallel
  local base_dir=_tmp/spec/$spec_subdir
  mkdir -p "$base_dir"

  local -a shells
  case $test_name in
    # Start using ASAN.  TODO: Use ASAN for everything.
    var-opt-patsub|alias)
      shells=( "${COMPARE_CPP_SHELLS[@]}" )
      ;;
    *)
      shells=( $REPO_ROOT/bin/osh $REPO_ROOT/_bin/cxx-dbg/osh )
      ;;
  esac

  # Output TSV so we can compare the data.  2022-01: Try 10 second timeout.
  sh-spec spec/$test_name.test.sh \
    --timeout 10 \
    --tsv-output $base_dir/${test_name}.tsv \
    "${shells[@]}" \
    "$@"
}

osh-all() {
  # Like test/spec.sh {oil,osh}-all, but it compares against different binaries

  # For debugging hangs
  #export MAX_PROCS=1

  # TODO: use ASAN for everything
  ninja _bin/cxx-{asan,dbg}/osh

  test/spec-runner.sh shell-sanity-check "${COMPARE_CPP_SHELLS[@]}"

  # $suite $compare_mode $spec_subdir
  test/spec-runner.sh all-parallel osh compare-cpp cpp || true  # OK if it fails

  html-summary
}

all() {
  # TODO: add oil-all eventually
  osh-all
}

soil-run() {
  local opt_bin=_bin/cxx-opt/osh

  # Run with optimized binary since it's faster
  ninja $opt_bin

  # Do less work to start
  # export NUM_SPEC_TASKS=8
  OSH_CC=$REPO_ROOT/$opt_bin all
}

console-row() {
  ### Print out a histogram of results

  awk '
FNR == 1 {
  #print FILENAME > "/dev/stderr" 
}
FNR != 1 {
  case_num = $1
  sh = $2
  result = $3

  if (sh == "osh") {
    osh[result] += 1
  } else if (sh == "osh_cpp") {  # bin/osh_cpp
    oe_py[result] += 1
  } else if (sh == "osh_ALT") {  # _bin/*/osh
    oe_cpp[result] += 1
  }
}

function print_hist(sh, hist) {
  printf("%s\t", sh)

  k = "pass"
  printf("%s %4d\t", k, hist[k])
  k = "FAIL"
  printf("%s %4d\t", k, hist[k])

  print ""

  # This prints N-I, ok, bug, etc.
  #for (k in hist) {
  #  printf("%s %s\t", k, hist[k])
  #}

}

END { 
  print_hist("osh", osh)
  print_hist("osh_cpp", oe_py)
  print_hist("osh_ALT", oe_cpp)
}
  ' "$@"
}

console-summary() {
  ### Report on our progress translating

  # Can't go at the top level because files won't exist!
  readonly TSV=(_tmp/spec/cpp/*.tsv)

  wc -l "${TSV[@]}"

  for file in "${TSV[@]}"; do
    echo
    echo "$file"
    console-row $file
  done

  echo
  echo "TOTAL"
  console-row "${TSV[@]}"
}

#
# HTML
#

summary-csv-row() {
  ### Print one row or the last total row
  if test $# -eq 1; then
    local spec_name=$1
    local -a tsv_files=(_tmp/spec/cpp/$spec_name.tsv)
  else
    local spec_name='TOTAL'
    local -a tsv_files=( "$@" )
  fi

  awk -v spec_name=$spec_name '
# skip the first row
FNR != 1 {
  case_num = $1
  sh = $2
  result = $3

  if (sh == "osh") {
    osh[result] += 1
  } else if (sh == "osh-cpp") {  # bin/osh
    osh_native[result] += 1
  }
}

END { 
  num_py = osh["pass"]
  num_cpp = osh_native["pass"] 
  if (spec_name == "TOTAL") {
    href = ""
  } else {
    href = sprintf("%s.html", spec_name)
  }

  if (num_py == num_cpp) {
    row_css_class = "cpp-good"  # green
  }

  printf("%s,%s,%s,%d,%d,%d\n",
         row_css_class,
         spec_name, href,
         num_py,
         num_cpp,
         num_py - num_cpp)
}
' "${tsv_files[@]}"
}

summary-csv() {
  # Can't go at the top level because files might not exist!
  cat <<EOF
ROW_CSS_CLASS,name,name_HREF,osh_py,osh_cpp,delta
EOF

  # total row rows goes at the TOP, so it's in <thead> and not sorted.
  summary-csv-row _tmp/spec/cpp/*.tsv

  head -n $NUM_SPEC_TASKS _tmp/spec/SUITE-osh.txt |
  while read spec_name; do
    summary-csv-row $spec_name
  done 
}

html-summary-header() {
  local prefix=../../..
  html-head --title 'Passing Spec Tests in C++' \
    $prefix/web/ajax.js \
    $prefix/web/table/table-sort.js $prefix/web/table/table-sort.css \
    $prefix/web/base.css \
    $prefix/web/spec-cpp.css

  table-sort-begin "width50"

  cat <<EOF
<p id="home-link">
  <!-- The release index is two dirs up -->
  <a href="../..">Up</a> |
  <a href="/">oilshell.org</a>
</p>

<h1>Passing Spec Tests</h1>

<p>These numbers measure the progress of Oil's C++ translation.
Compare with <a href="osh.html">osh.html</a>.
</p>

EOF
}

html-summary-footer() {
  cat <<EOF
<p>Generated by <code>test/spec-cpp.sh</code>.</p>
EOF
  table-sort-end "$@"
}

readonly BASE_DIR=_tmp/spec/cpp

# TODO: Use here-schema-tsv in test/tsv-lib.sh
here-schema() {
  ### Read a legible text format on stdin, and write CSV on stdout

  # This is a little like: https://wiki.xxiivv.com/site/tablatal.html
  # TODO: generalize this in stdlib/here.sh
  while read one two; do
    echo "$one,$two"
  done
}

html-summary() {
  local name=summary

  local out=$BASE_DIR/osh-summary.html

  summary-csv >$BASE_DIR/summary.csv 

  # The underscores are stripped when we don't want them to be!
  # Note: we could also put "pretty_heading" in the schema

  here-schema >$BASE_DIR/summary.schema.csv <<EOF
column_name   type
ROW_CSS_CLASS string
name          string
name_HREF     string
osh_py        integer
osh_cpp       integer
delta         integer
EOF

  { html-summary-header
    # total row isn't sorted
    web/table/csv2html.py --thead-offset 1 $BASE_DIR/summary.csv
    html-summary-footer $name
  } > $out
  echo "Wrote $out"
}

tsv-demo() {
  sh-spec spec/arith.test.sh --tsv-output _tmp/arith.tsv dash bash "$@"
  cat _tmp/arith.tsv
}

repro() {
  test/spec.sh alias -r 0 -p > _tmp/a
  ninja _bin/clang-dbg/oils-for-unix
  _bin/clang-dbg/oils-for-unix _tmp/a
}

repro-all() {
  OSH_CC=$REPO_ROOT/_bin/clang-dbg/oils-for-unix $0 all
}

"$@"
