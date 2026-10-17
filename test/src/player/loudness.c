// SPDX-License-Identifier: LGPL-2.1-or-later
/*****************************************************************************
 * loudness.c: audio loudness meter player test
 *****************************************************************************
 * Copyright (C) 2018-2025 VLC authors and VideoLAN
 *****************************************************************************/

#include "common.h"

static void
test_audio_loudness_meter_cb(vlc_tick_t date, double momentary_loudness,
                             void *data)
{
    (void) date;
    assert(momentary_loudness>= -23 -0.1 && momentary_loudness <= -23 +0.1);

    bool *loudness_meter_received = data;
    *loudness_meter_received = true;
}

static void
test_audio_loudness_meter(struct ctx *ctx)
{
    test_log("test_audio_loudness_meter\n");

    vlc_player_t *player = ctx->player;

    static const union vlc_player_metadata_cbs cbs = {
        test_audio_loudness_meter_cb,
    };

    if (!module_exists("ebur128"))
    {
        test_log("audio loudness meter test skipped\n");
        return;
    }

    struct media_params params = DEFAULT_MEDIA_PARAMS(VLC_TICK_FROM_SEC(1));
    params.track_count[AUDIO_ES] = 1;
    params.track_count[VIDEO_ES] = 0;
    params.track_count[SPU_ES] = 0;

    /* cf. EBU TECH 3341, Table 1. A 1000Hz stereo sine wave, with an amplitude
     * of -23dbFS (0.0707) should have a momentary loudness of -23LUFS */
    params.config = "audio[0]{sinewave=true,sinewave_frequency=1000"
                    ",sinewave_amplitude=0.0707}";
    player_set_next_mock_media(ctx, "media1", &params);

    bool loudness_meter_received = false;
    vlc_player_metadata_listener_id *listener_id =
        vlc_player_AddMetadataListener(player, VLC_PLAYER_METADATA_LOUDNESS_MOMENTARY,
                                       &cbs, &loudness_meter_received);
    assert(listener_id);

    player_start(ctx);
    wait_state(ctx, VLC_PLAYER_STATE_STARTED);
    wait_state(ctx, VLC_PLAYER_STATE_STOPPED);

    assert(loudness_meter_received);

    vlc_player_RemoveMetadataListener(player, listener_id);
    test_end(ctx);
}

static void
test_audio_loudness_noop_momentary_cb(vlc_tick_t date, double loudness,
                                      void *data)
{
    (void) date; (void) loudness; (void) data;
}

static void
test_audio_loudness_noop_full_cb(vlc_tick_t date,
                                 const struct vlc_audio_loudness *loudness,
                                 void *data)
{
    (void) date; (void) loudness; (void) data;
}

static void
test_audio_loudness_meter_listeners(struct ctx *ctx)
{
    test_log("test_audio_loudness_meter_listeners\n");

    vlc_player_t *player = ctx->player;

    static const union vlc_player_metadata_cbs momentary_cbs = {
        .on_momentary_loudness_changed = test_audio_loudness_noop_momentary_cb,
    };
    static const union vlc_player_metadata_cbs full_cbs = {
        .on_loudness_changed = test_audio_loudness_noop_full_cb,
    };

    if (!module_exists("ebur128"))
    {
        test_log("audio loudness meter listeners test skipped\n");
        return;
    }

    struct media_params params = DEFAULT_MEDIA_PARAMS(VLC_TICK_FROM_SEC(1));
    params.track_count[AUDIO_ES] = 1;
    params.track_count[VIDEO_ES] = 0;
    params.track_count[SPU_ES] = 0;
    player_set_next_mock_media(ctx, "media1", &params);

    vlc_player_metadata_listener_id *momentary_id =
        vlc_player_AddMetadataListener(player, VLC_PLAYER_METADATA_LOUDNESS_MOMENTARY,
                                       &momentary_cbs, NULL);
    assert(momentary_id);

    player_start(ctx);
    wait_state(ctx, VLC_PLAYER_STATE_PLAYING);

    /* Add and remove listeners (and so meter plugins) while the audio thread
     * is processing blocks and sending loudness events. Note: the lock
     * inversion that used to happen here (metadata_listeners_lock vs the
     * audio meter lock) is timing dependent and not reliably reproduced by
     * this test, which mostly checks that this sequence is safe. */
    const vlc_tick_t deadline = vlc_tick_now() + VLC_TICK_FROM_MS(500);
    while (vlc_tick_now() < deadline)
    {
        vlc_player_metadata_listener_id *full_id =
            vlc_player_AddMetadataListener(player, VLC_PLAYER_METADATA_LOUDNESS_FULL,
                                           &full_cbs, NULL);
        assert(full_id);
        vlc_player_RemoveMetadataListener(player, full_id);

        vlc_player_RemoveMetadataListener(player, momentary_id);
        momentary_id =
            vlc_player_AddMetadataListener(player, VLC_PLAYER_METADATA_LOUDNESS_MOMENTARY,
                                           &momentary_cbs, NULL);
        assert(momentary_id);

        /* Let the input thread send its events (and so feed the decoder) */
        vlc_player_Unlock(player);
        vlc_player_Lock(player);
    }

    vlc_player_RemoveMetadataListener(player, momentary_id);
    test_end(ctx);
}

int
main(void)
{
    struct ctx ctx;
    /* Test with --no-video */
    ctx_init(&ctx, DISABLE_VIDEO);
    test_audio_loudness_meter(&ctx);
    test_audio_loudness_meter_listeners(&ctx);
    ctx_destroy(&ctx);
    return 0;
}
