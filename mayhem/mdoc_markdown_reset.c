/*
 * Compiles usr.bin/mandoc/mdoc_markdown.c unmodified into this translation unit so the
 * fuzz harness can reset its file-scope state between inputs; markdown_mdoc() only
 * re-initialises outflags.
 */
#include "mdoc_markdown.c"

void
mayhem_markdown_reset(void)
{
	outflags = 0;
	escflags = 0;
	code_blocks = quote_blocks = list_blocks = 0;
	outcount = 0;
}
