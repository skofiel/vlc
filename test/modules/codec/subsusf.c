// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * subsusf.c: USF subtitles decoder tests
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "../../libvlc/test.h"
#include "../../../lib/libvlc_internal.h"
#include <vlc_common.h>
#include <vlc_modules.h>
#include <vlc_codec.h>
#include <vlc_subpicture.h>
#include <vlc_es.h>

struct test_owner {
    decoder_t dec;
    es_format_t fmt_in;
    unsigned queued;
};

static subpicture_t *spu_new(decoder_t *dec, const subpicture_updater_t *upd)
{
    (void) dec;
    return subpicture_New(upd);
}

static void spu_queue(decoder_t *dec, subpicture_t *spu)
{
    struct test_owner *owner = container_of(dec, struct test_owner, dec);
    owner->queued++;
    subpicture_Delete(spu);
}

static const struct decoder_owner_callbacks dec_cbs = {
    .spu = {
        .buffer_new = spu_new,
        .queue = spu_queue,
    },
};

static unsigned decode(libvlc_instance_t *vlc, const char *header,
                       const char *subtitle)
{
    struct test_owner *owner =
        vlc_object_create(VLC_OBJECT(vlc->p_libvlc_int), sizeof(*owner));
    assert(owner != NULL);
    owner->queued = 0;
    decoder_t *dec = &owner->dec;

    es_format_t fmt;
    es_format_Init(&fmt, SPU_ES, VLC_CODEC_USF);
    fmt.i_extra = strlen(header);
    fmt.p_extra = strdup(header);
    assert(fmt.p_extra != NULL);

    decoder_Init(dec, &owner->fmt_in, &fmt);
    es_format_Clean(&fmt);
    dec->cbs = &dec_cbs;

    dec->p_module = module_need(dec, "spu decoder", "subsusf", true);
    assert(dec->p_module != NULL);

    block_t *block = block_Alloc(strlen(subtitle));
    assert(block != NULL);
    memcpy(block->p_buffer, subtitle, block->i_buffer);
    block->i_pts = block->i_dts = VLC_TICK_0;
    block->i_length = VLC_TICK_FROM_SEC(1);

    int ret = dec->pf_decode(dec, block);
    assert(ret == VLCDEC_SUCCESS);

    unsigned queued = owner->queued;
    decoder_Clean(dec);
    es_format_Clean(&owner->fmt_in);
    vlc_object_delete(dec);
    return queued;
}

int main(void)
{
    test_init();

    libvlc_instance_t *vlc = libvlc_new(0, NULL);
    assert(vlc != NULL);

    /* Styles without name must be ignored (they can't be referenced, and
     * were crashing the lookup of the Default style) */
    static const char header_unnamed[] =
        "<USFSubtitles version=\"1.0\"><styles>"
        "<style><fontstyle face=\"Arial\"/></style>"
        "<style name=\"Default\"><fontstyle face=\"Arial\"/></style>"
        "</styles></USFSubtitles>";
    assert(decode(vlc, header_unnamed, "<text>hello</text>") == 1);

    static const char header_unnamed_only[] =
        "<USFSubtitles version=\"1.0\"><styles>"
        "<style><fontstyle face=\"Arial\"/></style>"
        "</styles></USFSubtitles>";
    assert(decode(vlc, header_unnamed_only, "<text>hello</text>") == 1);

    /* Unterminated style */
    static const char header_unterminated[] =
        "<USFSubtitles version=\"1.0\"><styles>"
        "<style name=\"Default\"><fontstyle face=\"Arial\"/>";
    assert(decode(vlc, header_unterminated, "<text>hello</text>") == 1);

    libvlc_release(vlc);
    return 0;
}
