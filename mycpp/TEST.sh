#!/usr/bin/env bash
#
# Run tests in this directory.
#
# Usage:
#   mycpp/TEST.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

REPO_ROOT=$(cd "$(dirname $0)/.."; pwd)
source build/common.sh
source cpp/NINJA-steps.sh
source devtools/common.sh
source soil/common.sh  # find-dir-html
source test/common.sh  # run-test-bin

# in case binaries weren't built
shopt -s failglob

export ASAN_OPTIONS='detect_leaks=0'

examples-variant() {
  ### Run all examples using a variant

  local compiler=${1:-cxx}
  local variant=${2:-gcevery}
  local do_benchmark=${3:-}

  banner "$0 examples-variant $compiler $variant"

  ninja mycpp-examples-$compiler-$variant

  local num_tests=0
  local num_failed=0
  local status=0

  local log_dir=_test/$compiler-$variant/mycpp/examples
  mkdir -p $log_dir

  for b in _bin/$compiler-$variant/mycpp/examples/*; do
    case $b in
      (*.stripped)  # just run the unstripped binary
        continue
        ;;
    esac

    local prefix="$log_dir/$(basename $b)"

    case $variant in
      (coverage)
        export LLVM_PROFILE_FILE=$prefix.profraw
        ;;
    esac

    local log="${prefix}${do_benchmark}.log"

    log "RUN $b > $log"

    local test_name=$(basename $b)
    if test -n "$do_benchmark" && [[ $test_name == test_* ]]; then
      log "Skipping $test_name in benchmark mode"
      continue
    fi

    set +o errexit
    BENCHMARK="$do_benchmark" $b >$log 2>&1
    status=$?
    set -o errexit

    if test "$status" -eq 0; then
      log 'OK'
    else
      log "FAIL with status $?"
      #return $status
      num_failed=$((num_failed + 1))
    fi

    num_tests=$((num_tests + 1))
  done

  log ''
  log "$num_failed of $num_tests tests failed"
  log ''
}

#
# 3 Variants x {test, benchmark}
#

# 10 segfaults
ex-gcevery() {
  local compiler=${1:-}
  examples-variant "$compiler" gcevery
}

# TOO SLOW to run.  It's garbage collecting all the time.
ex-gcevery-bench() {
  local compiler=${1:-}
  examples-variant "$compiler" gcevery '.BENCHMARK'
}

# PASS!
ex-asan() {
  local compiler=${1:-}
  examples-variant "$compiler" asan
}

# 2 of 18 tests failed: cartesian, parse
# So it does not catch the 10 segfaults that 'gcevery' catches with a few
# iterations!
ex-asan-bench() {
  local compiler=${1:-}
  examples-variant "$compiler" asan '.BENCHMARK'
}

# PASS!  Under both clang and GCC.
ex-ubsan() {
  local compiler=${1:-}
  examples-variant "$compiler" ubsan
}

# same as ASAN: 2 of 18
ex-ubsan-bench() {
  local compiler=${1:-}
  examples-variant "$compiler" ubsan '.BENCHMARK'
}

# PASS!
ex-opt() {
  local compiler=${1:-}
  examples-variant "$compiler" opt
}

# 2 of 18 tests failed
ex-opt-bench() {
  local compiler=${1:-}
  examples-variant "$compiler" opt '.BENCHMARK'
}

#
# Unit Tests
#

unit() {
  ### Run by test/cpp-unit.sh

  local compiler=${1:-cxx}
  local variant=${2:-gcevery}

  log ''
  log "$0 unit $compiler $variant"
  log ''


  # TODO: Exclude examples here
  # ninja mycpp-$variant
  ninja mycpp-unit-$compiler-$variant

  local log_dir=_test/$compiler-$variant/mycpp
  mkdir -p $log_dir

  for b in _bin/$compiler-$variant/mycpp/*; do
    if ! test -f $b; then
      continue
    fi

    local prefix=$log_dir/$(basename $b)
    local log=$prefix.log

    run-test-bin $b
  done
}

#
# Test failures
#

test-invalid-examples() {
  local mycpp=_bin/shwrap/mycpp_main
  ninja $mycpp
  for ex in mycpp/examples/invalid_*; do

    banner "$ex"

    set +o errexit
    $mycpp '.:pyext' _tmp/mycpp-invalid $ex
    local status=$?
    set -o errexit

    if test $status -ne 1; then
      die "mycpp $ex: expected status 1, got $status"
    fi

  done
}

test-runtime() {
  # Run other unit tests, e.g. the GC tests
  unit '' asan
  unit '' ubsan
  unit '' gcstats
  unit '' gcevery

  # Doesn't work yet because of GC_STATS num_live_objs_
  # unit '' sweepasan

  # Two tests that do pass
  ninja _bin/cxx-sweepasan/mycpp/marksweep_gc_test
  run-test-bin _bin/cxx-sweepasan/mycpp/marksweep_gc_test

  # Fails under ASAN; we should re-enable ASAN_OPTIONS=detect_leaks
  ninja _bin/cxx-sweepasan/mycpp/gc_builtins_test
  run-test-bin _bin/cxx-sweepasan/mycpp/gc_builtins_test

  ninja _bin/cxx-sweepasan/mycpp/gc_heap_test
  run-test-bin _bin/cxx-sweepasan/mycpp/gc_heap_test
}

#
# Translator
#

compare-examples() {
  banner 'compare-examples'

  ./NINJA-config.sh

  # 'mycpp-all' has other stuff like type checking alone, stripping, clang builds
  set +o errexit
  ninja mycpp-logs-equal
  local status=$?
  set -o errexit

  find-dir-html _test mycpp-examples

  # Now we want to zip up
  return $status
}

test-sweep-asan-leaks() {
  ninja _bin/cxx-sweepasan/mycpp/examples/fib_iter.mycpp
  ASAN_OPTIONS='' _bin/cxx-sweepasan/mycpp/examples/fib_iter.mycpp
}

test-translator() {
  ### Invoked by soil/worker.sh

  test-sweep-asan-leaks

  run-test-func test-invalid-examples _test/mycpp/test-invalid-examples.log

  # Runs test in cxx-asan variant, and benchmarks in cxx-opt variant
  compare-examples

  #
  # Now test under more variants
  #
  examples-variant '' sweepasan

  # NOTE: This has 10 crashes!  Because of the Cheney collector.
  # Heap-allocated tuple, etc.

  #examples-variant '' gcevery

}

unit-test-coverage() {
  ### Invoked by Soil

  unit clang coverage

  local out_dir=_test/clang-coverage/mycpp
  test/coverage.sh html-report $out_dir mycpp
}

examples-coverage() {
  ### Invoked by Soil

  examples-variant clang coverage

  local out_dir=_test/clang-coverage/mycpp/examples
  test/coverage.sh html-report $out_dir mycpp/examples
}

"$@"