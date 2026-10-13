const gba = @import("gba");

// Show panics on screen (and give lldb a `debug_panic.panic` symbol to break on).
pub const panic = gba.debug.std_panic;

export var header linksection(".gbaheader") = gba.Header.init("TXUSTRIS", "TXRS", "00", 0);

pub export fn main() void {
    // Initialize a color palette.
    gba.display.bg_palette.banks[0][0] = .black;
    gba.display.bg_palette.banks[0][1] = .white;
    
    // Initialize a background, to be used for displaying text.
    const normal_bg_map = gba.display.BackgroundMap.setup(0, .{
        .base_screenblock = 31,
        .size = .size_32x32,
    });
    normal_bg_map.getBaseScreenblock().fillLinear(.{});
    
    // Draw text to the tile memory used by the initialized background.
    const text_surface = gba.display.bg_blocks.getSurface4Bpp(0, 32, 32);
    text_surface.draw().text("Hello, world!", .init(1), .{
        .x = 96,
        .y = 70,
        .line_height = 16,
    });
    
    // Initialize the display.
    gba.display.ctrl.* = .initMode0(.{ .bg0 = true });
    
    // Enable VBlank interrupts.
    // This will allow running the main loop once per frame.
    gba.display.status.vblank_interrupt = true;
    gba.interrupt.enable.vblank = true;
    gba.interrupt.master.enable = true;
    
    // Main loop.
    while (true) {
        gba.bios.vblankIntrWait();
    }
}
