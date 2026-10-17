// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * parsers.c: playlist parsers unit testing (RAM, B4S)
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
                   const char *module, const char *url,
                   const char *data, size_t datasz,
                   int(*checkfunc)(const char *, const input_item_node_t *))
{
    stream_t *s = vlc_stream_MemoryNew(vlc->p_libvlc_int, (uint8_t *)data, datasz, true);
    if(!s)
        BAILOUT(run);

    demux_t *pl = demux_New(VLC_OBJECT(vlc->p_libvlc_int), module, url, s, NULL);
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

#define RAM_URL "http://example.com/playlist.ram"

/* Properly terminated clipinfo */
static const char ramplaylist0[] =
    "http://example.com/a.rm?clipinfo=\"title=foo|artist name=bar\"\n";

static int check_ram0(const char *run, const input_item_node_t *p_node)
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

static int check_nothing(const char *run, const input_item_node_t *p_node)
{
    (void) p_node;
    (void) run;
    return 0;
}

#define B4S_URL "http://example.com/playlist.b4s"

/* The first line is skipped by the B4S parser. The first entry has no
 * Playstring and must be ignored. */
static const char b4splaylist0[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    "<WinampXML><playlist num_entries=\"2\">"
    "<entry><Name>no playstring</Name></entry>"
    "<entry Playstring=\"http://example.com/a.mp3\"><Name>a</Name></entry>"
    "</playlist></WinampXML>\n";

static int check_b4s0(const char *run, const input_item_node_t *p_node)
{
    EXPECT(p_node->i_children == 1);
    const input_item_t *p_item = p_node->pp_children[0]->p_item;
    EXPECT(!strcmp(p_item->psz_uri, "http://example.com/a.mp3"));
    EXPECT(!strcmp(p_item->psz_name, "a"));
    return 0;
}

int main(void)
{
    test_init();

    libvlc_instance_t *vlc = libvlc_new(0, NULL);
    if(!vlc)
        return 1;

    int ret = runtest("ram0", vlc, "ram", RAM_URL,
                      ramplaylist0, sizeof(ramplaylist0) - 1, check_ram0);
    if(!ret)
        ret = runtest("ram1", vlc, "ram", RAM_URL,
                      ramplaylist1, sizeof(ramplaylist1) - 1, check_nothing);
    if(!ret)
        ret = runtest("b4s0", vlc, "shout-b4s", B4S_URL,
                      b4splaylist0, sizeof(b4splaylist0) - 1, check_b4s0);

    libvlc_release(vlc);
    return ret;
}
