// leaky_pylib.h: Replacement for pylib/*.py

#ifndef LEAKY_PYLIB_H
#define LEAKY_PYLIB_H

#if 1  // TODO: switch this off
#include "mycpp/mylib_leaky.h"
#else
#include "mycpp/mylib2.h"
#endif

namespace os_path {

Str* rstrip_slashes(Str* s);

}  // namespace os_path

namespace path_stat {

bool exists(Str* path);

}  // namespace path_stat

#endif  // LEAKY_PYLIB_H