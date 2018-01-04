#!/usr/bin/env python
# Copyright 2016 Andy Chu. All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
from __future__ import print_function
"""
builtins.py - Implementation of builtins, along with their metadata.

- used for lookup in cmd_exec.py
  - need a hash of builtin names for quick testing?
- handle completion of builtin NAMES -- pass to completion.py
  - handle aliases : . and source, [ and test
- handle flags they take
  - handle completion of builtin FLAGS
- Add the "help" builtin itself

NOTE: bash has help -d -m -s.  Default is -s, like a man page.

Links on special builtins:
http://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_14

- syntax errors in special builtins may cause the shell to abort, but NOT for
  regular builtins?
"""

import os
import sys

from core import args
from core import legacy
from core import lexer
from core import runtime
from core import util
from core import state
from core.id_kind import Id

from osh import lex

from _devbuild.gen import osh_help  # generated file

value_e = runtime.value_e
scope_e = runtime.scope_e
span_e = runtime.span_e
var_flags_e = runtime.var_flags_e
log = util.log
e_die = util.e_die



# NOTE: NONE is a special value.
# TODO:
# - Make a table of name to enum?  source, dot, etc.
# - So you can just add "complete" and have it work.

EBuiltin = util.Enum('EBuiltin', """
NONE READ ECHO SHIFT
CD PUSHD POPD DIRS
EXPORT UNSET SET SHOPT
TRAP UMASK
EXIT SOURCE DOT EVAL EXEC WAIT JOBS 
COMPLETE COMPGEN DEBUG_LINE
TRUE FALSE
COLON
TEST BRACKET GETOPTS
COMMAND TYPE HELP
""".split())


# These can't be redefined by functions.
# http://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_14
# On the other hand, 'cd' CAN be redefined.
#
# NOTE: OSH treats these specially:
# - break/continue/return
# - local/readonly
_SPECIAL_BUILTINS = [
    'break', ':', 'continue', '.', 'eval', 'exec', 'exit', 'export',
    'readonly', 'return', 'set', 'shift', 'times', 'trap', 'unset',

    # local and declare are not POSIX, but should be here since export and
    # readonly are.
    'local', 'declare',
]

# TODO: Add a way to register.
_BUILTINS = ['echo', 'read']


class BuiltinDef(object):
  """
  NOTE: Used by completion.py.
  """
  def __init__(self):
    # Is this what we want?
    names = set()
    names.update(_BUILTINS)
    names.update(_SPECIAL_BUILTINS)
    # TODO: Also complete keywords first for, while, etc.  Bash/zsh/fish/yash
    # all do this.  Also do/done

    self.arg_specs = {}
    self.to_complete = sorted(names)

  def GetNamesToComplete(self):
    """For completion of builtin names."""
    return self.to_complete

  def Register(self, name, help_topic=None):
    help_topic = help_topic or name
    arg_spec = args.BuiltinFlags()
    self.arg_specs[name] = arg_spec
    return arg_spec


# Global instance for "metaprogramming" before main().
BUILTIN_DEF = BuiltinDef()


def _Register(name, help_topic=None):
  return BUILTIN_DEF.Register(name, help_topic=help_topic)



# TODO: Resolve() and EBuiltin kind of useless?  We could just test for string
# equality directly.  Or do we want to cache this lookup so it isn't done on
# say every iteration of a loop?

def ResolveSpecial(argv0):
  # TODO: Add more special builtins here
  if argv0 == "export":
    return EBuiltin.EXPORT
  elif argv0 == "exit":
    return EBuiltin.EXIT
  elif argv0 == ":":
    return EBuiltin.COLON

  return EBuiltin.NONE


def Resolve(argv0):
  # TODO: ResolveSpecialBuiltin first, then ResolveFunction, then
  # ResolveOtherBuiltin.  In other words, you can't redefine special builtins
  # with functions, but you can redefine other builtins.

  # For completion, this is a flat list of names.  Although coloring them
  # would be nice.

  # TODO: Use Buitlins to initialize.

  if argv0 == "read":
    return EBuiltin.READ
  elif argv0 == "echo":
    return EBuiltin.ECHO
  elif argv0 == "cd":
    return EBuiltin.CD
  elif argv0 == "shift":
    return EBuiltin.SHIFT
  elif argv0 == "pushd":
    return EBuiltin.PUSHD
  elif argv0 == "popd":
    return EBuiltin.POPD
  elif argv0 == "dirs":
    return EBuiltin.DIRS

  elif argv0 == "source":
    return EBuiltin.SOURCE
  elif argv0 == ".":
    return EBuiltin.DOT

  elif argv0 == "trap":
    return EBuiltin.TRAP
  elif argv0 == "umask":
    return EBuiltin.UMASK
  elif argv0 == "eval":
    return EBuiltin.EVAL
  elif argv0 == "exec":
    return EBuiltin.EXEC
  elif argv0 == "wait":
    return EBuiltin.WAIT
  elif argv0 == "jobs":
    return EBuiltin.JOBS

  elif argv0 == "set":
    return EBuiltin.SET
  elif argv0 == "shopt":
    return EBuiltin.SHOPT
  elif argv0 == "unset":
    return EBuiltin.UNSET
  elif argv0 == "complete":
    return EBuiltin.COMPLETE
  elif argv0 == "compgen":
    return EBuiltin.COMPGEN

  elif argv0 == "true":
    return EBuiltin.TRUE
  elif argv0 == "false":
    return EBuiltin.FALSE

  elif argv0 == "test":
    return EBuiltin.TEST
  elif argv0 == "[":
    return EBuiltin.BRACKET

  elif argv0 == "getopts":
    return EBuiltin.GETOPTS

  elif argv0 == "command":
    return EBuiltin.COMMAND

  elif argv0 == "type":
    return EBuiltin.TYPE

  elif argv0 == "help":
    return EBuiltin.HELP

  elif argv0 == "debug-line":
    return EBuiltin.DEBUG_LINE

  return EBuiltin.NONE


R = lexer.R
C = lexer.C

# TODO:
# - See if re2c supports {1,2} etc.
# - the DOLLAR_SQ lex state needs most of this logic.

ECHO_LEXER = lexer.SimpleLexer([
  R(r'\\[0abeEfrtnv\\]', Id.Char_OneChar),
  C(r'\c', Id.Char_Stop),

  # Note: tokens above \0377 can either be truncated or be flagged a syntax
  # error in strict mode.
  R(r'\\0[0-7]{1,3}', Id.Char_Octal),

  # \x6 is valid in bash
  R(r'\\x[0-9a-fA-F]{1,2}', Id.Char_Hex),
  R(r'\\u[0-9]{1,4}', Id.Char_Unicode4),
  R(r'\\U[0-9]{1,8}', Id.Char_Unicode8),

  R(r'[^\\]+', Id.Char_Literals),
  R(r'\\.', Id.Char_Literals),

  # Backslash that ends the string.
  R(r'\\$', Id.Char_Literals),
  # For re2c.  TODO: need to make that translation.
  C('\\\0', Id.Char_Literals),
])


_ONE_CHAR = {
    '0': '\0',
    'a': '\a',
    'b': '\b',
    'e': '\x1b',
    'E': '\x1b',
    'f': '\f',
    'n': '\n',
    'r': '\r',
    't': '\t',
    'v': '\v',
    '\\': '\\',
}


# Strict mode syntax errors:
#
# \x is a syntax error -- needs two digits (It's like this in C)
# \0777 is a syntax error -- we shouldn't do modulus
# \d could be a syntax error -- it is better written as \\d

def _EvalStringPart(id_, value):
  # TODO: This has to go in the compile stage for DOLLAR_SQ strings.

  if id_ == Id.Char_OneChar:
    c = value[1]
    return _ONE_CHAR[c]

  elif id_ == Id.Char_Stop:  # \c returns a special sentinel
    return None

  elif id_ == Id.Char_Octal:
    # TODO: Error checking for \0777
    s = value[2:]
    i = int(s, 8)
    if i >= 256:
      i = i % 256
      # NOTE: This is for strict mode
      #raise AssertionError('Out of range')
    return chr(i)

  elif id_ == Id.Char_Hex:
    s = value[2:]
    i = int(s, 16)
    return chr(i)

  elif id_ == Id.Char_Unicode4:
    s = value[2:]
    i = int(s, 16)
    return unichr(i)

  elif id_ == Id.Char_Unicode8:
    s = value[2:]
    i = int(s, 16)
    return unichr(i)

  elif id_ == Id.Char_Literals:
    return value

  else:
    raise AssertionError


echo_spec = _Register('echo')
echo_spec.ShortFlag('-e')  # no backslash escapes
echo_spec.ShortFlag('-n')


def Echo(argv):
  """
  echo builtin.

  set -o sane-echo could do the following:
  - only one arg, no implicit joining.
  - no -e: should be echo c'one\ttwo\t'
  - no -n: should be write 'one'

  multiple args on a line:
  echo-lines one two three
  """
  # NOTE: both getopt and optparse are unsuitable for 'echo' because:
  # - 'echo -c' should print '-c', not fail
  # - echo '---' should print ---, not fail

  arg, arg_index = echo_spec.ParseLikeEcho(argv)
  argv = argv[arg_index:]
  if arg.e:
    new_argv = []
    for a in argv:
      parts = []
      for id_, value in ECHO_LEXER.Tokens(a):
        p = _EvalStringPart(id_, value)

        # Unusual behavior: '\c' prints what is there and aborts processing!
        if p is None:
          new_argv.append(''.join(parts))
          for i, a in enumerate(new_argv):
            if i != 0:
              sys.stdout.write(' ')  # arg separator
            sys.stdout.write(a)
          return 0  # EARLY RETURN

        parts.append(p)
      new_argv.append(''.join(parts))

    # Replace it
    argv = new_argv

  #log('echo argv %s', argv)
  for i, a in enumerate(argv):
    if i != 0:
      sys.stdout.write(' ')  # arg separator
    sys.stdout.write(a)
  if not arg.n:
    sys.stdout.write('\n')

  # Do I need the flush?  Had a problem here under load, but it might not have
  # been because of that.
  # File "/home/andy/git/oil/bin/../core/cmd_exec.py", line 251, in _RunBuiltin
  #   status = builtin.Echo(argv)
  # File "/home/andy/git/oil/bin/../core/builtin.py", line 431, in Echo
  #   sys.stdout.flush()
  # IOError: [Errno 32] Broken pipe

  sys.stdout.flush()
  return 0


def Exit(argv):
  if len(argv) > 1:
    util.error('exit: too many arguments')
    return 1
  try:
    code = int(argv[0])
  except IndexError:
    code = 0
  except ValueError as e:
    print("Invalid argument %r" % argv[0], file=sys.stderr)
    code = 1  # Runtime Error
  # TODO: Should this be turned into our own SystemExit exception?
  sys.exit(code)


import getopt

def Wait(argv, waiter, job_state, mem):
  """
  wait: wait [-n] [id ...]
      Wait for job completion and return exit status.

      Waits for each process identified by an ID, which may be a process ID or a
      job specification, and reports its termination status.  If ID is not
      given, waits for all currently active child processes, and the return
      status is zero.  If ID is a a job specification, waits for all processes
      in that job's pipeline.

      If the -n option is supplied, waits for the next job to terminate and
      returns its exit status.

      Exit Status:
      Returns the status of the last ID; fails if ID is invalid or an invalid
      option is given.

  # Job spec, %1 %2, %%, %?a etc.

  http://mywiki.wooledge.org/BashGuide/JobControl#jobspec

  This is different than a PID?  But it does have a PID.
  """
  # NOTE: echo can't use getopt because of 'echo ---'
  # But that's a special case; the rest of the builtins can use it.
  # We must respect -- everywhere, EXCEPT echo.  'wait -- -n' should work must work.

  opt_n = False

  try:
    opts, args = getopt.getopt(argv, 'n')
  except getopt.GetoptError as e:
    util.usage(str(e))
    sys.exit(2)
  for name, val in opts:
    if name == '-n':
      opt_n = True
    else:
      raise AssertionError

  if opt_n:
    # wait -n returns the exit status of the process.  But how do you know
    # WHICH process?  That doesn't seem useful.
    log('wait next')
    if waiter.Wait():
      return waiter.last_status
    else:
      return 127  # nothing to wait for

  if not args:
    log('wait all')
    # TODO: get all background jobs from JobState?
    i = 0
    while True:
      if not waiter.Wait():
        break  # nothing to wait for
      i += 1
      if job_state.AllDone():
        break

    log('waited for %d processes', i)
    return 0

  # Get list of jobs.  Then we need to check if they are ALL stopped.
  # Returns the exit code of the last one on the COMMAND LINE, not the exit
  # code of last one to FINSIH.

  status = 1  # error
  for a in args:
    # NOTE: osh doesn't accept 'wait %1' yet
    try:
      jid = int(a)
    except ValueError:
      util.error('Invalid argument %r', a)
      return 127

    job = job_state.jobs.get(jid)
    if job is None:
      util.error('No such job: %s', jid)
      return 127

    st = job.WaitUntilDone(waiter)
    if isinstance(st, list):
      status = st[-1]
      state.SetGlobalArray(mem, 'PIPESTATUS', [str(p) for p in st])
    else:
      status = st

  return status


def Jobs(argv, job_state):
  """List jobs."""
  job_state.List()
  return 0


# Summary:
# - Split with IFS, except \ can escape them!  This is different than the
# algorithm for splitting words (at least the way I've represented it.)
# - And

# Bash manual:
# - If there are more words than names, the remaining words and their
# intervening delimiters are assigned to the last name.
# - If there are fewer words read from the input stream than names, the
# remaining names are assigned empty values. 
# - The characters in the value of the IFS variable are used to split the line
# into words using the same rules the shell uses for expansion (described
# above in Word Splitting).
# - The backslash character '\' may be used to remove any special meaning for
# the next character read and for line continuation.
#
# Hm but word splitting isn't affected by \<space>
#
# I think I have to make two passes.
#
# 1. Process backslashes (or don't if it's -r)
# 2. Split.

def _AppendParts(s, spans, max_results, join_next, parts):
  """
  Args:
    s: The original string
    spans: List of (span, end_index)
    max_results: the maximum number of parts we want
    join_next: Whether to join the next span to the previous part.  This
    happens in two cases:
      - when we have '\ '
      - and when we have more spans # than max_results.
  """
  start_index = 0
  # If the last span was black, and we get a backslash, set join_next to merge
  # two black spans.
  last_span_was_black = False

  for span_type, end_index in spans:
    if span_type == span_e.Black:
      if join_next and parts:
        parts[-1] += s[start_index:end_index]
        join_next = False
      else:
        parts.append(s[start_index:end_index])
      last_span_was_black = True

    elif span_type == span_e.Delim:
      if join_next:
        parts[-1] += s[start_index:end_index]
        join_next = False
      last_span_was_black = False

    elif span_type == span_e.Backslash:
      if last_span_was_black:
        join_next = True
      last_span_was_black = False

    if len(parts) >= max_results:
      join_next = True

    start_index = end_index

  done = True
  if spans:
    #log('%s %s', s, spans)
    #log('%s', spans[-1])
    last_span_type, _ = spans[-1]
    if last_span_type == span_e.Backslash:
      done = False

  #log('PARTS %s', parts)
  return done, join_next


READ_SPEC = _Register('read')
READ_SPEC.ShortFlag('-r')
READ_SPEC.ShortFlag('-n', args.Int)


def Read(argv, splitter, mem):
  arg, i = READ_SPEC.Parse(argv)

  names = argv[i:]
  if arg.n is not None:  # read a certain number of bytes
    try:
      name = names[0]
    except IndexError:
      name = 'REPLY'  # default variable name
    s = os.read(sys.stdin.fileno(), arg.n)
    #log('read -n: %s = %s', name, s)

    state.SetLocalString(mem, name, s)
    # NOTE: Even if we don't get n bytes back, there is no error?
    return 0

  if not names:
    names.append('REPLY')

  # leftover words assigned to the last name
  max_results = len(names)

  # We have to read more than one line if there is a line continuation (and
  # it's not -r).

  parts = []
  join_next = False
  while True:
    line = sys.stdin.readline()
    #log('LINE %r', line)
    if not line:  # EOF
      status = 1
      break

    if line.endswith('\n'):  # strip trailing newline
      line = line[:-1]
      status = 0
    else:
      # odd bash behavior: fail even if we can set variables.
      status = 1

    spans = splitter.SplitForRead(line, not arg.r)
    done, join_next = _AppendParts(line, spans, max_results, join_next, parts)

    #log('PARTS %s continued %s', parts, continued)
    if done:
      break

  for i in xrange(max_results):
    try:
      s = parts[i]
    except IndexError:
      s = ''  # if there are too many variables
    #log('read: %s = %s', names[i], s)
    state.SetLocalString(mem, names[i], s)

  return status


def Shift(argv, mem):
  if len(argv) > 1:
    util.error('shift: too many arguments')
    return 1
  try:
    n = int(argv[0])
  except IndexError:
    n = 1
  except ValueError as e:
    print("Invalid shift argument %r" % argv[1], file=sys.stderr)
    return 1  # runtime error

  return mem.Shift(n)


def Cd(argv, mem, dir_stack):
  # TODO: Parse flags, error checking, etc.
  try:
    dest_dir = argv[0]
  except IndexError:
    val = mem.GetVar('HOME')
    if val.tag == value_e.Undef:
      util.error("$HOME isn't defined")
      return 1
    elif val.tag == value_e.Str:
      dest_dir = val.s
    elif val.tag == value_e.StrArray:
      util.error("$HOME shouldn't be an array.")
      return 1

  if dest_dir == '-':
    old = mem.GetVar('OLDPWD', scope_e.GlobalOnly)
    if old.tag == value_e.Undef:
      log('OLDPWD not set')
      return 1
    elif old.tag == value_e.Str:
      dest_dir = old.s
      print(dest_dir)  # Shells print the directory
    elif old.tag == value_e.StrArray:
      # TODO: Prevent the user from setting OLDPWD to array (or maybe they
      # can't even set it at all.)
      raise AssertionError('Invalid OLDPWD')

  # NOTE: We can't call os.getcwd() because it can raise OSError if the
  # directory was removed (ENOENT.)

  pwd = mem.GetVar('PWD')
  assert pwd.tag == value_e.Str, pwd  # TODO: Need a general scheme to avoid
  state.SetGlobalString(mem, 'OLDPWD', pwd.s)
  try:
    os.chdir(dest_dir)
  except OSError as e:
    # TODO: Add line number, etc.
    util.error("cd %r: %s", dest_dir, os.strerror(e.errno))
    return 1

  state.SetGlobalString(mem, 'PWD', dest_dir)  # Set $PWD.
  dir_stack.Reset()  # for pushd/popd/dirs

  return 0


WITH_PREFIX = 1
WITHOUT_PREFIX = 2
SINGLE_LINE = 3

def _PrintDirStack(dir_stack, style):
  """Helper for 'dirs'."""

  if style == WITH_PREFIX:
    for i, entry in enumerate(dir_stack.Iter()):
      print('%2d  %s' % (i, entry))

  elif style == WITHOUT_PREFIX:
    for entry in dir_stack.Iter():
      print(entry)

  elif style == SINGLE_LINE:
    print(' '.join(dir_stack.Iter()))

  sys.stdout.flush()


def Pushd(argv, dir_stack):
  num_args = len(argv)
  if num_args <= 0:
    util.error('pushd: no other directory')
    return 1
  elif num_args > 1:
    util.error('pushd: too many arguments')
    return 1

  dest_dir = argv[0]
  try:
    os.chdir(dest_dir)
  except OSError as e:
    util.error("pushd: %r: %s", dest_dir, os.strerror(e.errno))
    return 1

  dir_stack.Push(dest_dir)
  _PrintDirStack(dir_stack, SINGLE_LINE)
  return 0


def Popd(argv, dir_stack):
  dest_dir = dir_stack.Pop()
  if dest_dir is None:
    util.error('popd: directory stack is empty')
    return 1

  try:
    os.chdir(dest_dir)
  except OSError as e:
    util.error("popd: %r: %s", dest_dir, os.strerror(e.errno))
    return 1

  _PrintDirStack(dir_stack, SINGLE_LINE)
  return 0


DIRS_SPEC = _Register('dirs')
DIRS_SPEC.ShortFlag('-c')
DIRS_SPEC.ShortFlag('-l')
DIRS_SPEC.ShortFlag('-p')
DIRS_SPEC.ShortFlag('-v')

def Dirs(argv, dir_stack):
  arg, i = DIRS_SPEC.Parse(argv)
  if arg.l:
    util.warn('*** dirs -l not implemented ***')
  # Following bash behavior
  if arg.c:
    dir_stack.Reset()
  elif arg.v:
    _PrintDirStack(dir_stack, WITH_PREFIX)
  elif arg.p:
    _PrintDirStack(dir_stack, WITHOUT_PREFIX)
  else:
    _PrintDirStack(dir_stack, SINGLE_LINE)
  return 0


EXPORT_SPEC = _Register('export')
EXPORT_SPEC.ShortFlag('-n')


def Export(argv, mem):
  arg, i = EXPORT_SPEC.Parse(argv)
  if arg.n:
    for name in argv[i:]:
      m = lex.VAR_NAME_RE.match(name)
      if not m:
        raise args.UsageError('export: Invalid variable name %r' % name)

      # NOTE: bash doesn't care if it wasn't found.
      _ = mem.ClearFlag(name, var_flags_e.Exported, scope_e.Dynamic)
  else:
    for arg in argv[i:]:
      parts = arg.split('=', 1)
      if len(parts) == 1:
        name = parts[0]
        val = None  # Creates an empty variable
      else:
        name, s = parts
        val = runtime.Str(s)

      m = lex.VAR_NAME_RE.match(name)
      if not m:
        raise args.UsageError('export: Invalid variable name %r' % name)

      #log('%s %s', name, val)
      mem.SetVar(
          runtime.LhsName(name), val, (var_flags_e.Exported,), scope_e.Dynamic)

  return 0


def AddOptionsToArgSpec(spec):
  """Shared between 'set' builtin and the shell's own arg parser."""
  for short_flag, opt_name in state.SET_OPTIONS:
    spec.Option(short_flag, opt_name)


SET_SPEC = args.FlagsAndOptions()
AddOptionsToArgSpec(SET_SPEC)


def SetExecOpts(exec_opts, opt_changes):
  """Used by bin/oil.py too."""
  for opt_name, b in opt_changes:
    exec_opts.SetOption(opt_name, b)


def Set(argv, exec_opts, mem):
  # TODO:
  # - How to integrate this with auto-completion?  Have to handle '+'.

  if not argv:  # empty
    # TODO:
    # - This should be set -o, not plain 'set'.
    # - When no arguments are given, it shows functions/vars?  Why not show
    # other state?
    exec_opts.ShowOptions([])
    return 0

  arg, i = SET_SPEC.Parse(argv)

  SetExecOpts(exec_opts, arg.opt_changes)
  if arg.saw_double_dash or i != len(argv):  # set -u shouldn't affect argv
    mem.SetArgv(argv[i:])
  return 0

  # TODO:
  # - STRICT: should be a combination of errexit,nounset,pipefail, plus
  #   strict-*, plus IFS?  Caps because it's a composite.
  # - SANE: disallow constructs like $* ?  That can be done with an explicit
  #   join, like s="$@" or something?
  #   or s="$@"  # osh: join
  #
  # This should be done at the module level.
  #
  # Maybe:
  # option -o foo
  # option +o foo
  # But it can only be in a module with all functions?  I don't want the state
  # to persist.
  # It's a flag on functions?  Were they defined in a FILE with -o?
  #
  # source
  # This way they're not global variables.
  # or what about shopt?
  #
  # Ways of setting options:
  #   set -o +o
  #   shopt -o +o
  #   shopt -s / shopt -u
  #
  # shopt is also a runtime thing, not a delaration.
  #
  # PROBLEM:
  # shopt -s noglob
  # set -o pipefail
  # source 'lib.sh'  # behavior is changed.  Although not if you put everything
  # in functions!  In that case, it's really the settings in main() that matter
  # (as long as nobody later turns things off.)


SHOPT_SPEC = _Register('shopt')
SHOPT_SPEC.ShortFlag('-s')  # set
SHOPT_SPEC.ShortFlag('-u')  # unset
SHOPT_SPEC.ShortFlag('-o')  # use 'set -o' up names
SHOPT_SPEC.ShortFlag('-p')  # print


def Shopt(argv, exec_opts):
  arg, i = SHOPT_SPEC.Parse(argv)

  if arg.p:  # print values
    if arg.o:  # use set -o names
      exec_opts.ShowOptions(argv[i:])
    else:
      exec_opts.ShowShoptOptions(argv[i:])
    return 0

  b = None
  if arg.s:
    b = True
  elif arg.u:
    b = False

  if b is None:
    raise NotImplementedError  # Display options

  for opt_name in argv[i:]:
    if arg.o:
      exec_opts.SetOption(opt_name, b)
    else:
      exec_opts.SetShoptOption(opt_name, b)

  return 0


UNSET_SPEC = _Register('unset')
UNSET_SPEC.ShortFlag('-v')
UNSET_SPEC.ShortFlag('-f')


# TODO:
# - Parse lvalue expression: unset 'a[ i - 1 ]'.  Static or dynamic parsing?
def Unset(argv, mem, funcs):
  arg, i = UNSET_SPEC.Parse(argv)

  for name in argv[i:]:
    if arg.f:
      if name in funcs:
        del funcs[name]
    elif arg.v:
      ok, _  = mem.Unset(runtime.LhsName(name), scope_e.Dynamic)
      if not ok:
        util.error("Can't unset readonly variable %r", name)
        return 1
    else:
      # Try to delete var first, then func.
      ok, found = mem.Unset(runtime.LhsName(name), scope_e.Dynamic)
      if not ok:
        util.error("Can't unset readonly variable %r", name)
        return 1
      #log('%s: %s', name, found)
      if not found:
        if name in funcs:
          del funcs[name]

  return 0


def _ResolveNames(names, funcs, path_val):
  if path_val.tag == value_e.Str:
    path_list = path_val.s.split(':')
  else:
    path_list = []  # treat as empty path

  results = []
  for name in names:
    if name in funcs:
      kind = ('function', name)
    elif Resolve(name) != EBuiltin.NONE:
      kind = ('builtin', name)
    elif ResolveSpecial(name) != EBuiltin.NONE:
      kind = ('builtin', name)
    elif lex.IsOtherBuiltin(name):  # declare, continue, etc.
      kind = ('builtin', name)
    elif lex.IsKeyword(name):
      kind = ('keyword', name)
    else:
      # Now look for files.
      found = False
      for path_dir in path_list:
        full_path = os.path.join(path_dir, name)
        if os.path.exists(full_path):
          kind = ('file', full_path)
          found = True
          break
      if not found:  # Nothing printed, but status is 1.
        kind = (None, None)
    results.append(kind)

  return results
    

COMMAND_SPEC = _Register('command')
COMMAND_SPEC.ShortFlag('-v')
COMMAND_SPEC.ShortFlag('-V')

def Command(argv, funcs, path_val):
  arg, i = COMMAND_SPEC.Parse(argv)
  status = 0
  if arg.v:
    for kind, arg in _ResolveNames(argv[i:], funcs, path_val):
      if kind is None:
        status = 1  # nothing printed, but we fail
      else:
        # This is for -v, -V is more detailed.
        print(arg)
  else:
    util.warn('*** command without -v not not implemented ***')
    status = 1

  return status


TYPE_SPEC = _Register('type')
TYPE_SPEC.ShortFlag('-t')

def Type(argv, funcs, path_val):
  arg, i = TYPE_SPEC.Parse(argv)

  status = 0
  if not arg.t:
    util.warn("*** 'type' builtin called without -t ***")
    status = 1
    # Keep going anyway

  for kind, arg in _ResolveNames(argv[i:], funcs, path_val):
    if kind is None:
      status = 1  # nothing printed, but we fail
    else:
      print(kind)

  return status


def Trap(argv, traps):
  # TODO: register trap

  # Example:
  # trap -- 'echo "hi  there" | wc ' SIGINT
  #
  # Then hit Ctrl-C.
  #
  # Yeah you need the EvalHelper.  traps is a list of signals to parsed
  # NODES.

  util.warn('*** trap not implemented ***')
  return 0


def Umask(argv):
  if len(argv) == 0:
    # umask() has a dumb API: you can't get it without modifying it first!
    # NOTE: dash disables interrupts around the two umask() calls, but that
    # shouldn't be a concern for us.  Signal handlers won't call umask().
    mask = os.umask(0)
    os.umask(mask)  # 
    print('0%03o' % mask)  # octal format
    return 0

  if len(argv) == 1:
    a = argv[0]
    try:
      new_mask = int(a, 8)
    except ValueError:
      # NOTE: This happens if we have '8' or '9' in the input too.

      util.warn('*** umask with symbolic input not implemented ***')
      return 1
    else:
      os.umask(new_mask)
      return 0

  raise args.UsageError('umask: unexpected arguments')


def _ParseOptSpec(spec_str):
  spec = {}
  i = 0
  n = len(spec_str)
  while True:
    if i >= n:
      break
    c = spec_str[i]
    key = '-' + c
    spec[key] = False
    i += 1
    if i >= n:
      break
    # If the next character is :, change the value to True.
    if spec_str[i] == ':':
      spec[key] = True
      i += 1
  return spec


def _GetOpts(spec, mem, optind):
  optarg = ''  # not set by default

  v2 = mem.GetArgNum(optind)
  if v2.tag == value_e.Undef:  # No more arguments.
    return 1, '?', optarg, optind
  assert v2.tag == value_e.Str

  current = v2.s

  if not current.startswith('-'):  # The next arg doesn't look like a flag.
    return 1, '?', optarg, optind

  # It looks like an argument.  Stop iteration by returning 1.
  if current not in spec:  # Invalid flag
    optind += 1
    return 0, '?', optarg, optind

  optind += 1
  opt_char = current[-1]

  needs_arg = spec[current]
  if needs_arg:
    v3 = mem.GetArgNum(optind)
    if v3.tag == value_e.Undef:
      util.error('getopts: option %r requires an argument', current)
      # Hm doesn't cause status 1?
      return 0, '?', optarg, optind
    assert v3.tag == value_e.Str

    optarg = v3.s
    optind += 1

  return 0, opt_char, optarg, optind


# spec string -> {flag, arity}
_GETOPTS_CACHE = {}

def GetOpts(argv, mem):
  """
  Vars to set:
    OPTIND - initialized to 1 at startup
    OPTARG - argument
  Vars used:
    OPTERR: disable printing of error messages
  """
  try:
    # NOTE: If first char is a colon, error reporting is different.  Alpine
    # might not use that?
    spec_str = argv[0]
    var_name = argv[1]
  except IndexError:
    raise args.UsageError('getopts optstring name [arg]')

  try:
    spec = _GETOPTS_CACHE[spec_str]
  except KeyError:
    spec = _ParseOptSpec(spec_str)
    _GETOPTS_CACHE[spec_str] = spec

  # These errors are fatal errors, not like the builtin exiting with code 1.
  # Because the invariants of the shell have been violated!
  v = mem.GetVar('OPTIND')
  if v.tag != value_e.Str:
    e_die('OPTIND should be a string, got %r', v)
  try:
    optind = int(v.s)
  except ValueError:
    e_die("OPTIND doesn't look like an integer, got %r", v.s)

  status, opt_char, optarg, optind = _GetOpts(spec, mem, optind)

  state.SetGlobalString(mem, var_name, opt_char)
  state.SetGlobalString(mem, 'OPTARG', optarg)
  state.SetGlobalString(mem, 'OPTIND', str(optind))
  return status


def Help(argv, loader):
  # TODO: Need $VERSION inside all pages?
  try:
    topic = argv[0]
  except IndexError:
    topic = 'help'

  if topic == 'toc':
    # Just show the raw source.
    f = loader.open('doc/osh-quick-ref-toc.txt')
  else:
    try:
      section_id = osh_help.TOPIC_LOOKUP[topic]
    except KeyError:
      util.error('No help topics match %r', topic)
      return 1
    else:
      try:
        f = loader.open('_build/osh-quick-ref/%s' % section_id)
      except IOError as e:
        util.error(str(e))
        raise AssertionError('Should have found %r' % section_id)

  for line in f:
    sys.stdout.write(line)
  f.close()
  return 0


def DebugLine(argv, status_lines):
  # TODO: Maybe add a position flag?  Like debug-line -n 1 'foo'
  # And enforce that you get a single arg?

  status_lines[0].Write('DEBUG: %s', ' '.join(argv))
  return 0


def main(argv):
  # Localization: Optionally  use GNU gettext()?  For help only.  Might be
  # useful in parser error messages too.  Good thing both kinds of code are
  # generated?  Because I don't want to deal with a C toolchain for it.

  loader = util.GetResourceLoader()
  Help([], loader)

  for name, spec in BUILTIN_DEF.arg_specs.iteritems():
    print(name)
    spec.PrintHelp(sys.stdout)
    print()


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError as e:
    print('FATAL: %s' % e, file=sys.stderr)
    sys.exit(1)
