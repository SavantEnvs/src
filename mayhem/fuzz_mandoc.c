/*
 * libFuzzer harness for mandoc(1) (usr.bin/mandoc): parse one manual page
 * (mdoc(7), man(7), roff(7), tbl(7), eqn(7)) and run every output formatter over
 * the resulting tree, as main.c does for a single file.
 *
 * .so requests are not honoured (MPARSE_SO is off) so an input cannot read files.
 */
#include <sys/types.h>

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "mandoc.h"
#include "roff.h"
#include "mandoc_xr.h"
#include "mandoc_parse.h"
#include "manconf.h"
#include "main.h"

static struct mparse *mp;
void mayhem_man_reset(void);
void mayhem_markdown_reset(void);

static struct manoutput outconf;
static FILE *msg_out;
static char msg_buf[1 << 16], out_buf[1 << 16];

int
LLVMFuzzerInitialize(int *argc, char ***argv)
{
	/* Diagnostics and formatter output go to fixed in-memory buffers, rewound per input. */
	if ((msg_out = fmemopen(msg_buf, sizeof(msg_buf), "w")) == NULL ||
	    (stdout = fmemopen(out_buf, sizeof(out_buf), "w")) == NULL)
		return 1;
	mandoc_msg_setoutfile(msg_out);
	mandoc_msg_setmin(MANDOCERR_BASE);

	mchars_alloc();
	mp = mparse_alloc(MPARSE_UTF8 | MPARSE_LATIN1 | MPARSE_VALIDATE,
	    MANDOC_OS_OPENBSD, NULL);
	memset(&outconf, 0, sizeof(outconf));
	return 0;
}

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	struct roff_meta *meta;
	void *html_out, *ascii_out, *ps_out;
	int fd;

	fd = memfd_create("page", 0);
	if (fd == -1)
		return 0;
	if (size > 0 && write(fd, data, size) != (ssize_t)size) {
		close(fd);
		return 0;
	}
	lseek(fd, 0, SEEK_SET);

	mparse_reset(mp);
	mandoc_msg_setinfilename("fuzz.1");
	mparse_readfd(mp, fd, "fuzz.1");
	close(fd);

	/*
	 * Every formatter's state is rebuilt per input: the output objects are allocated
	 * afresh and the file-scope state in mdoc_man.c and mdoc_markdown.c is reset.
	 */
	html_out = html_alloc(&outconf);
	ascii_out = ascii_alloc(&outconf);
	ps_out = ps_alloc(&outconf);
	mayhem_man_reset();
	mayhem_markdown_reset();
	mandoc_xr_reset();
	meta = mparse_result(mp);

	if (meta->macroset == MACROSET_MDOC) {
		html_mdoc(html_out, meta);
		tree_mdoc(NULL, meta);
		man_mdoc(NULL, meta);
		terminal_mdoc(ascii_out, meta);
		terminal_mdoc(ps_out, meta);
		markdown_mdoc(NULL, meta);
	} else if (meta->macroset == MACROSET_MAN) {
		html_man(html_out, meta);
		tree_man(NULL, meta);
		terminal_man(ascii_out, meta);
		terminal_man(ps_out, meta);
	}
	html_free(html_out);
	ascii_free(ascii_out);
	pspdf_free(ps_out);
	fflush(stdout);
	rewind(stdout);
	rewind(msg_out);
	return 0;
}
