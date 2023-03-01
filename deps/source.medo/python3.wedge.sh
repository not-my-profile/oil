# Wedge definition for python3
#
# Loaded by deps/wedge.sh.

set -o nounset
set -o pipefail
set -o errexit

# sourced
WEDGE_NAME='python3'
WEDGE_VERSION='3.10.4'

WEDGE_TARBALL_NAME='Python'

wedge-build() {
  local src_dir=$1
  local build_dir=$2
  local install_dir=$3

  pushd $build_dir

  # Note: we need PY3_BUILD_DEPS on the base image to get a working 'pip
  # install'
  # And then Dockerfile.* may need the corresponding runtime deps

  time $src_dir/configure --prefix=$install_dir

  time make

  popd
}

wedge-install() {
  local build_dir=$1
  local install_dir=$2

  pushd $build_dir

  # It makes a symlink called python3
  #
  # NOTE: There's no option to strip the binary?
  # The whole package is 265 MB, but 200 MB of it is the Python stdlib.
  # Seemingly lots of __pycache__ dirs

  time make install

  popd
}

wedge-smoke-test() {
  local install_dir=$1

  $install_dir/bin/python3 -c 'print("hi from python 3")'
}