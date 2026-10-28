//! Background music: streams 8-bit PCM from ROM through DirectSound A.
//!
//! Once started, the hardware does all the per-sample work:
//!   Timer 0 overflows 13379 times per second
//!     -> on each overflow, DirectSound A plays the next sample from its FIFO
//!     -> when the FIFO runs low, DMA1 refills it with 16 more bytes from ROM
//! Timer 1 runs in cascade mode, counting timer 0 overflows (= samples played),
//! so `update` knows exactly when the track is about to end and must loop.

const gba = @import("gba");

/// Signed 8-bit mono PCM, converted from assets/music.ogg by build.zig.
const samples align(4) = @embedFile("music").*;

/// 13379 Hz is a classic GBA rate: one sample every 1254 CPU cycles,
/// which is exactly 224 samples per frame (280896 cycles / 1254).
const sample_rate = 13379;
const cycles_per_sample = 16_777_216 / sample_rate; // 1254
const samples_per_frame = 224;

var last_tick: u16 = 0; // timer 1's value at the previous `update`
var played: u32 = 0; // samples played since the last (re)start

/// Start playing the track, looping forever. Call once at boot.
pub fn play() void {
    // Master enable must come first: sound registers ignore writes while it's off.
    gba.sound.status.* = .init(true);

    // DirectSound A at full volume on both speakers, clocked by timer 0.
    // Note: this also writes the DMG (PSG) settings; set `.dmg` here too if you add PSG sound effects.
    gba.sound.ctrl.* = .{ .dsound = .{
        .volume_a = .percent_100,
        .left_a = true,
        .right_a = true,
        .timer_a = 0,
        .reset_a = true,
    } };

    // Timer 1 counts timer 0 overflows, i.e. samples played.
    gba.timers[1] = .init(0, .{ .mode = .cascade, .enable = true });

    restart();

    // Timer 0 overflows every `cycles_per_sample` cycles: it counts up from this reload value to 0x10000.
    gba.timers[0] = .init(0x10000 - cycles_per_sample, .{ .enable = true });
}

/// Call once per frame. Loops the track just before its end.
pub fn update() void {
    const now = gba.timers[1].counter;
    played += now -% last_tick; // wrapping subtraction survives the 16-bit counter overflowing
    last_tick = now;

    // Restart a frame early: we only check once per frame, and DMA reads up to
    // 32 bytes ahead of playback, so waiting for the exact end would play
    // whatever comes after the samples in ROM.
    if (played + samples_per_frame >= samples.len) restart();
}

/// Point DMA1 back at the start of the samples.
fn restart() void {
    const channel = &gba.mem.dma[1];
    channel.ctrl = .{}; // stop DMA1 before re-pointing it
    channel.source = &samples;
    channel.dest = gba.sound.fifo_a;
    channel.count = 4; // ignored in FIFO mode: every refill request moves 4 words (16 samples)
    channel.ctrl = .{
        .dest = .fixed, // always write into the FIFO register
        .dma_repeat = true, // keep going on every FIFO request
        .size = .bits_32,
        .timing = .special, // DMA1/2 "special" = triggered by the sound FIFO
        .enabled = true,
    };

    played = 0;
    last_tick = gba.timers[1].counter;
}
