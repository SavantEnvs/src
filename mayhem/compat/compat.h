/* Minimal OpenBSD-on-glibc shims; force-included (-include) into the OpenBSD sources we build. */
#ifndef MAYHEM_COMPAT_H
#define MAYHEM_COMPAT_H
#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#define _PATH_LOCALE "/usr/share/locale"
#ifndef EFTYPE
#define EFTYPE EINVAL
#endif
#ifndef __dead
#define __dead __attribute__((__noreturn__))
#endif
#ifndef MACHINE
#define MACHINE "amd64"
#endif

void *recallocarray(void *, size_t, size_t, size_t);
long long strtonum(const char *, long long, long long, const char **);

const char *getprogname(void);
#ifndef DEF_WEAK
#define DEF_WEAK(x)
#endif

static inline int pledge(const char *p, const char *e) { (void)p; (void)e; return 0; }
static inline int unveil(const char *p, const char *m) { (void)p; (void)m; return 0; }
#endif
