/*
 * Compiles usr.bin/mandoc/mdoc_man.c unmodified into this translation unit so the fuzz
 * harness can reset its file-scope state between inputs; mdoc_man.c keeps a nested-list
 * stack and a font stack that man_mdoc() does not clear.
 */
#include "mdoc_man.c"

void
mayhem_man_reset(void)
{
	memset(Bl_stack, 0, sizeof(Bl_stack));
	memset(Bl_stack_post, 0, sizeof(Bl_stack_post));
	Bl_stack_len = 0;
	TPremain = 0;
	outflags = 0;
	fontqueue.tail = fontqueue.head;
	if (fontqueue.head != NULL)
		*fontqueue.head = 'R';
}
