// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * ram.c: RAM playlist unit testing
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc/vlc.h>
#include "../../../../lib/libvlc_internal.h"
#include "../../../libvlc/test.h"

#include <vlc_common.h>
#include <vlc_demux.h>
#include <vlc_meta.h>
#include <vlc_input_item.h>

#define BAILOUT(run) { fprintf(stderr, "failed %s line %d\n", run, __LINE__); \
                        return 1; }
#define EXPECT(foo) if(!(foo)) BAILOUT(run)

static int runtest(const char *run,
                   libvlc_instance_t *vlc,
                   const char *data, size_t datasz,
                   int(*checkfunc)(const char *, const input_item_node_t *))
{
    stream_t *s = vlc_stream_MemoryNew(vlc->p_libvlc_int, (uint8_t *)data, datasz, true);
    if(!s)
        BAILOUT(run);

    demux_t *pl = demux_New(VLC_OBJECT(vlc->p_libvlc_int), "ram",
                            "http://example.com/playlist.ram", s, NULL);
    if(!pl || !pl->pf_readdir)
    {
        vlc_stream_Delete(s);
        BAILOUT(run);
    }

    int ret = 1;
    input_item_t *p_item = input_item_New(NULL, NULL);
    if(p_item)
    {
        input_item_node_t *p_node = input_item_node_Create(p_item);
        if(p_node)
        {
            pl->pf_readdir(pl, p_node);
            ret = checkfunc(run, p_node);
            input_item_node_Delete(p_node);
        }
        input_item_Release(p_item);
    }

    demux_Delete(pl);

    return ret;
}

/* Properly terminated clipinfo */
static const char ramplaylist0[] =
    "http://example.com/a.rm?clipinfo=\"title=foo|artist name=bar\"\n";

static int check0(const char *run, const input_item_node_t *p_node)
{
    EXPECT(p_node->i_children == 1);
    EXPECT(p_node->pp_children[0]->p_item->psz_uri != NULL);
    return 0;
}

/* Unterminated clipinfo, with a MRL that can't be resolved (invalid port),
 * so that it is kept as is: this must not read past the end of the string. */
static const char ramplaylist1[] =
    "http://h:x/a.rm?clipinfo=\"title=foo|artist name=bar\n"
    "http://h:x/b.rm?clipinfo=\"title=foo\n";

static int check1(const char *run, const input_item_node_t *p_node)
{
    (void) p_node;
    (void) run;
    return 0;
}

int main(void)
{
    test_init();

    libvlc_instance_t *vlc = libvlc_new(0, NULL);
    if(!vlc)
        return 1;

    int ret = runtest("run0", vlc, ramplaylist0, sizeof(ramplaylist0) - 1, check0);
    if(!ret)
        ret = runtest("run1", vlc, ramplaylist1, sizeof(ramplaylist1) - 1, check1);

    libvlc_release(vlc);
    return ret;
}
