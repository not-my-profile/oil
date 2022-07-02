#!/usr/bin/env python2
"""
NINJA_config.py
"""
from __future__ import print_function

import os
import sys

from cpp import NINJA_subgraph as cpp_subgraph
from mycpp import NINJA_subgraph as mycpp_subgraph

sys.path.append('.')
from vendor import ninja_syntax


def log(msg, *args):
  if args:
    msg = msg % args
  print(msg, file=sys.stderr)


class UnitTestWriter(object):

  def __init__(self, f):
    self.f = f
    self.func_names = []

  def comment(self, s):
    self.f.write('# %s\n' % s)

  def newline(self):
    self.f.write('\n')

  def unit_test(self, func_name, ninja_target):
    """
    Args:
      name: function name in u.sh
      ninja_target: the file that should be built first, and then run
    """
    self.f.write("""\
%s() {
  ninja %s
  run-test %s "$@"
}
""" % (func_name, ninja_target, ninja_target))

    self.func_names.append(func_name)

  def header(self):
    self.f.write("""
#!/usr/bin/env bash
#
# TASK.sh: Tasks that invoke ninja.
#
# Generated by %s.

set -o errexit
set -o nounset
set -o pipefail

run-test() {
  echo '    ---'
  echo "    $0 running $@"
  echo '    ---'

  "$@"
}

""" % __file__)

  def footer(self):
    all_lines = '\n'.join(self.func_names)

    self.f.write("""\
list() {
  ### list tests to run
echo '
%s
'
}

all-serial() {
%s
}
""" % (all_lines, all_lines))

    self.f.write("""\
"$@"
""")


# The file Ninja runs by default.
BUILD_NINJA = 'build.ninja'

# Tasks that invoke Ninja
TASK_SH = 'TASK.sh'


def main(argv):
  try:
    action = argv[1]
  except IndexError:
    action = 'ninja'

  if action == 'ninja':
    n = ninja_syntax.Writer(open(BUILD_NINJA, 'w'))

    u_file = open(TASK_SH, 'w')
    u = UnitTestWriter(u_file)
    u.header()

    cpp_subgraph.NinjaGraph(n, u)

    n.newline()
    n.newline()

    mycpp_subgraph.NinjaGraph(n, u)

    u.footer()

    u_file.close()
    os.chmod(TASK_SH, 0o755)

    log('%s: Wrote %s', argv[0], BUILD_NINJA)


  elif action == 'shell':
    out = '_build/oil-native.sh'
    with open(out, 'w') as f:
      cpp_subgraph.ShellFunctions(f, argv[0])
    log('%s: Wrote %s', argv[0], out)

  else:
    raise RuntimeError('Invalid action %r' % action)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError as e:
    print('FATAL: %s' % e, file=sys.stderr)
    sys.exit(1)