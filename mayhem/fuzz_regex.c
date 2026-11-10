/*
 * libFuzzer harness for OpenBSD's POSIX regex (lib/libc/regex): regcomp, regexec,
 * regerror and regfree, built from the tree's own sources under obsd_* names.
 *
 * Input: byte 0 selects the regcomp flags, byte 1 the regexec flags, the rest is
 * "pattern NUL subject" (no NUL: the whole rest is the pattern).
 */
#include <regex.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	static const int cmap[5] = { REG_EXTENDED, REG_ICASE, REG_NOSUB,
	    REG_NEWLINE, REG_NOSPEC };
	static const int emap[5] = { REG_NOTBOL, REG_NOTEOL, REG_STARTEND,
	    REG_LARGE, REG_BACKR };
	regex_t re;
	regmatch_t pm[10];
	char errbuf[128];
	char *pat, *subj;
	const uint8_t *nul;
	size_t patlen, sublen;
	int cflags = 0, eflags = 0, i, rc;

	if (size < 2)
		return -1;
	for (i = 0; i < 5; i++) {
		if (data[0] & (1 << i))
			cflags |= cmap[i];
		if (data[1] & (1 << i))
			eflags |= emap[i];
	}
	data += 2;
	size -= 2;

	nul = memchr(data, 0, size);
	patlen = nul != NULL ? (size_t)(nul - data) : size;
	sublen = nul != NULL ? size - patlen - 1 : 0;

	pat = malloc(patlen + 1);
	subj = malloc(sublen + 1);
	if (pat == NULL || subj == NULL)
		abort();
	memcpy(pat, data, patlen);
	pat[patlen] = '\0';
	if (sublen > 0)
		memcpy(subj, data + patlen + 1, sublen);
	subj[sublen] = '\0';

	rc = regcomp(&re, pat, cflags);
	if (rc != 0) {
		regerror(rc, &re, errbuf, sizeof(errbuf));
	} else {
		pm[0].rm_so = 0;
		pm[0].rm_eo = (regoff_t)sublen;
		rc = regexec(&re, subj, 10, pm, eflags);
		if (rc != 0 && rc != REG_NOMATCH)
			regerror(rc, &re, errbuf, sizeof(errbuf));
		regfree(&re);
	}
	free(pat);
	free(subj);
	return 0;
}
