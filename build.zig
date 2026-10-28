const std = @import("std");
const gba = @import("ziggba").gba;

const rom_name = "txustris";

/// Build the ROM.
/// Pass -Ddebug for an unoptimized build that's nicer to step through.
pub fn build(std_b: *std.Build) void {
    // Initialize a wrapper around `std.Build` with GBA-specific helpers.
    const b = gba.GbaBuild.create(std_b);
    // Create a build step to compile the ROM file.
    const rom = b.addExecutable(.{
        .name = rom_name,
        .root_source_file = b.path("src/main.zig"),
        .build_options = .{ .text_charsets = .{ .latin = true } },
    });

    // Convert the block sprite to 4bpp tiles, embedded via `@embedFile("block_tiles")`.
    // Index 0 is reserved for transparency, leaving room for the PNG's 9 grays.
    const block = b.addConvertImage(.{
        .path = b.path("assets/block8.png"),
        .format = .tiles_4bpp,
        .palettizer = .{ .naive = 16 },
    });
    rom.addAsset("block_tiles", block.data);
    rom.addAsset("block_pal", block.palette);

    // Convert the music to raw signed 8-bit mono PCM at 13379 Hz for DirectSound,
    // embedded via `@embedFile("music")` (see src/music.zig). Needs ffmpeg on PATH.
    const music = std_b.addSystemCommand(&.{ "ffmpeg", "-loglevel", "error", "-y", "-i" });
    music.addFileArg(b.path("assets/music.ogg"));
    music.addArgs(&.{ "-ac", "1", "-ar", "13379", "-f", "s8" });
    rom.addAsset("music", music.addOutputFileArg("music.raw"));

    // Also install the ELF (zig-out/bin/txustris) so lldb has symbols.
    std_b.installArtifact(rom.step);

    const run_cmd = std_b.addSystemCommand(&.{"mgba"});
    run_cmd.addFileArg(std_b.graph.path(.install_bin, "txustris.gba"));
    run_cmd.step.dependOn(std_b.getInstallStep());

    std_b.step("run", "Run the ROM in mGBA").dependOn(&run_cmd.step);

    // mGBA starts paused with a GDB stub on :2345; attach with `lldb -s gba.lldb`.
    const debug_cmd = std_b.addSystemCommand(&.{ "mgba", "-g" });
    debug_cmd.addFileArg(rom.rom);
    std_b.step("debug", "Run the ROM in mGBA, paused, waiting for a debugger on :2345").dependOn(&debug_cmd.step);
}
