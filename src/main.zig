const std = @import("std");
const gba = @import("gba");
const random = @import("random.zig");

pub const panic = gba.debug.std_panic;

export var header linksection(".gbaheader") = gba.Header.init("TXUSTRIS", "TXRS", "00", 0);

const DAS_FRAMES = 12;
const ARR_FRAMES = 3;

const GRAVITY_FRAMES = 48;
const SOFT_DROP_FRAMES = 2;

const LOCK_DELAY_FRAMES: u8 = 30;
const MAX_LOCK_RESETS: u8 = 15;

const block_tiles align(4) = embed("block_tiles");
const block_pal align(4) = embed("block_pal");

const bg_tiles align(4) = embed("block_tiles");
const bg_pal align(4) = embed("block_pal");

fn embed(comptime name: []const u8) [@embedFile(name).len]u8 {
    return @embedFile(name).*;
}

const block_grays: *const [block_pal.len / 2]gba.ColorRgb555 = @ptrCast(&block_pal);

const block_size = 8;

const Piece = struct {
    cells: [4][4][2]u2, // 4 sets of 16 bytes
    tint: gba.ColorRgb555, // u16
};

const pieces = [_]Piece{
    .{ .cells = .{ // long bar
        .{ .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 }, .{ 3, 1 } },
        .{ .{ 1, 0 }, .{ 1, 1 }, .{ 1, 2 }, .{ 1, 3 } },
        .{ .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 }, .{ 3, 1 } },
        .{ .{ 1, 0 }, .{ 1, 1 }, .{ 1, 2 }, .{ 1, 3 } },
    }, .tint = .cyan },
    .{ .cells = .{ // down-looking indent
        .{ .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 }, .{ 1, 2 } },
        .{ .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 2 } },
        .{ .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 } },
        .{ .{ 1, 0 }, .{ 1, 1 }, .{ 2, 1 }, .{ 1, 2 } },
    }, .tint = .magenta },
    .{ .cells = .{ // square
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } },
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } },
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } },
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } },
    }, .tint = .yellow },
    .{ .cells = .{ // L
        .{ .{ 1, 0 }, .{ 1, 1 }, .{ 1, 2 }, .{ 2, 2 } },
        .{ .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 }, .{ 0, 2 } },
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 1, 2 } },
        .{ .{ 2, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 } },
    }, .tint = .rgb(31, 16, 0) },
    .{ .cells = .{ // h-flipped L
        .{ .{ 1, 0 }, .{ 1, 1 }, .{ 0, 2 }, .{ 1, 2 } },
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 } },
        .{ .{ 1, 0 }, .{ 2, 0 }, .{ 1, 1 }, .{ 1, 2 } },
        .{ .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 }, .{ 2, 2 } },
    }, .tint = .blue },
    .{ .cells = .{ // _=-
        .{ .{ 1, 0 }, .{ 2, 0 }, .{ 0, 1 }, .{ 1, 1 } },
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 2 } },
        .{ .{ 1, 0 }, .{ 2, 0 }, .{ 0, 1 }, .{ 1, 1 } },
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 2 } },
    }, .tint = .green },
    .{ .cells = .{ // -=_
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 2, 1 } },
        .{ .{ 2, 0 }, .{ 1, 1 }, .{ 2, 1 }, .{ 1, 2 } },
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 2, 1 } },
        .{ .{ 2, 0 }, .{ 1, 1 }, .{ 2, 1 }, .{ 1, 2 } },
    }, .tint = .red },
};

fn bounds(piece_index: u4) [4][2][2]u2 {
    var out: [4][2][2]u2 = @splat(.{ .{ 3, 3 }, .{ 0, 0 } });
    const rotations = pieces[piece_index].cells;
    for (rotations, 0..) |rotated_piece, idx| {
        for (rotated_piece) |cell| {
            out[idx][0][0] = @min(out[idx][0][0], cell[0]);
            out[idx][0][1] = @min(out[idx][0][1], cell[1]);
            out[idx][1][0] = @max(out[idx][1][0], cell[0]);
            out[idx][1][1] = @max(out[idx][1][1], cell[1]);
        }
    }
    return out;
}

fn computePieceBounds() [7][4][2][2]u2 {
    var out: [7][4][2][2]u2 = undefined;
    for (0..7) |piece_idx| {
        out[piece_idx] = bounds(piece_idx);
    }
    return out;
}

const piece_bounds = computePieceBounds();

inline fn isWithinXBounds(piece_index: u4, x: i16, rotation: u4) bool {
    const b = piece_bounds[piece_index][rotation];
    return x + b[0][0] >= 0 and x + b[1][0] < GRID_WIDTH;
}

fn tintChannel(gray: u5, tint: u5) u5 {
    return @intCast(@as(u16, gray) * tint / 31);
}

fn darken(color: u5) u5 {
    return @intCast(@as(u16, color) / 6);
}

fn loadSpriteData() void {
    gba.display.memcpyBackgroundTiles4Bpp(1, @ptrCast(&block_tiles));
    gba.display.memcpyObjectTiles4Bpp(0, @ptrCast(&bg_tiles));

    for (block_grays, 0..) |gray, i| {
        gba.display.bg_palette.banks[7][i] = .rgb(darken(gray.r), darken(gray.g), darken(gray.b));
    }

    for (pieces, 0..) |piece, bank| {
        for (block_grays, 0..) |gray, i| {
            gba.display.bg_palette.banks[bank][i] = .rgb(
                tintChannel(gray.r, piece.tint.r),
                tintChannel(gray.g, piece.tint.g),
                tintChannel(gray.b, piece.tint.b),
            );
            gba.display.obj_palette.banks[bank][i] = .rgb(
                tintChannel(gray.r, piece.tint.r),
                tintChannel(gray.g, piece.tint.g),
                tintChannel(gray.b, piece.tint.b),
            );
        }
    }
}

const ShadowOAM = [128]gba.display.Object;

inline fn gridX(x: i16) i16 {
    return @intCast((grid_x_start + x) * block_size);
}

inline fn gridY(y: i16) i16 {
    return @intCast((grid_y_start + y) * block_size);
}


const GRID_WIDTH = 10;
const GRID_HEIGHT = 20;

const Cell = enum(u4) {
    empty = 8,
    _
};

const DebugScenario = enum(u4) {
    almost_two_lines,
    two_non_consecutive_lines,
};

const Grid = struct {
    _grid: [GRID_WIDTH][GRID_HEIGHT]Cell,

    fn init() Grid {
        return .{ ._grid = @splat(@splat(.empty)) };
    }

    fn setDebugScenario(self: *Grid, scenario: DebugScenario) void {
        switch (scenario) {
            .almost_two_lines => {
                for (18..20) |row_idx| {
                    for (0..GRID_WIDTH) |col_idx| {
                        if (col_idx != 7)  {
                            self._grid[col_idx][row_idx] = @fromBackingInt(@intCast(random.qran_range(0, 6)));
                        }
                    }
                }
            },
            .two_non_consecutive_lines => {
                for (17..20) |row_idx| {
                    for (0..GRID_WIDTH) |col_idx| {
                        if (row_idx == 18 and col_idx != 7)  {
                            self._grid[col_idx][row_idx] = @fromBackingInt(@intCast(random.qran_range(0, 6)));
                        } else if (row_idx != 18 and col_idx != 5) {
                            self._grid[col_idx][row_idx] = @fromBackingInt(@intCast(random.qran_range(0, 6)));
                        }
                    }
                }
            }
        }
    }

    fn fits(self: *Grid, piece_type: u4, rotation: u4, x: i16, y: i16) bool {
        const b = piece_bounds[piece_type][rotation];
        const within_x_grid_bounds = x + b[0][0] >= 0 and x + b[1][0] < GRID_WIDTH;
        const within_y_grid_bounds = y + b[0][1] >= 0 and y + b[1][1] < GRID_HEIGHT;
        if (!within_x_grid_bounds or !within_y_grid_bounds) return false;

        for (pieces[piece_type].cells[rotation]) |coord| {
            const grid_x: usize = @intCast(x + coord[0]);
            const grid_y: usize = @intCast(y + coord[1]);
            if (self._grid[grid_x][grid_y] != .empty) {
                return false;
            }
        }
        return true;
    }

    fn freezePiece(self: *Grid, piece_type: u4, rotation: u4, x: i16, y: i16) void {
        for (pieces[piece_type].cells[rotation]) |coord| {
            const grid_x: usize = @intCast(x + coord[0]);
            const grid_y: usize = @intCast(y + coord[1]);
            self._grid[grid_x][grid_y] = @fromBackingInt(piece_type);
        }
    }

    fn reRenderFrozenPieces(self: *Grid, grid_map: *gba.display.BackgroundMap) void {
        for (self._grid, 0..) |column, x| {
            for (column, 0..) |cell, y| {
                if (cell == .empty) {
                    grid_map.getBaseScreenblock().set(
                        @intCast(grid_x_start + x),
                        @intCast(grid_y_start + y),
                        .{ .tile = 1, .palette = 7 }
                    );
                } else {
                    grid_map.getBaseScreenblock().set(
                        @intCast(grid_x_start + x),
                        @intCast(grid_y_start + y),
                        .{ .tile = 1, .palette = @backingInt(cell) }
                    );
                }
            }
        }
    }

    fn _getFullLines(self: *Grid) [GRID_HEIGHT]bool {
        var full_lines: [GRID_HEIGHT]bool = @splat(false);

        for (0..GRID_HEIGHT) |row| {
            var full_line = true;
            for (0..GRID_WIDTH) |col| {
                if (self._grid[col][row] == .empty) {
                    full_line = false;
                }
            }
            full_lines[row] = full_line;
        }

        return full_lines;
    }

    fn getFullLines(self: *Grid) u32 {
        const full_lines = self._getFullLines();

        var count: u32 = 0;
        for (full_lines) |line| {
            if (line) { count += 1; }
        }

        return count;
    }
    
    fn hasFullLines(self: *Grid) bool {
        return self.getFullLines() > 0;
    }

    fn moveLine(self: *Grid, from: usize, to: usize) void {
        for (0..GRID_WIDTH) |col_idx| {
            self._grid[col_idx][to] = self._grid[col_idx][from];
            self._grid[col_idx][from] = .empty;
        }
    }

    fn clearLine(self: *Grid, row_idx: usize) void {
        for (0..GRID_WIDTH) |col_idx| {
            self._grid[col_idx][row_idx] = .empty;
        }
    }

    fn deleteFullLines(self: *Grid) void {
        const full_lines = self._getFullLines();

        for (0..GRID_HEIGHT) |row_idx| {
            if (full_lines[row_idx]) {
                const clearing_region_len = row_idx + 1;
                for (0..clearing_region_len) |clearing_row_idx| {
                    const target_row_idx = clearing_region_len - 1 - clearing_row_idx;
                    if (target_row_idx > 0) {
                        self.moveLine(target_row_idx-1, target_row_idx);
                    } else {
                        self.clearLine(target_row_idx);
                    }
                }
            }
         }
    }
};

export const save_chip align(4) = "SRAM_V113".*;
const EXPECTED_SAVE_MAGIC = "TXRS";
const SAVE_VERSION: u8 = 1;

const SaveData = extern struct {
    magic: [4]u8, // 0..3
    scores: [5]u32, // 4..23
    version: u8, // 24
    checksum: u8, // 25   checksum of the first 25 bytes
    _pad: [2]u8 = @splat(0), // 26..27

    fn calculateChecksum(bytes: []const u8) u8 {
        var c: u8 = 0xA5;
        for (bytes) |b| c ^= b;
        return c;
    }

    fn load() SaveData {
        var buf: [@sizeOf(SaveData)]u8 = undefined;
        for (&buf, 0..) |*b, i| b.* = gba.mem.sram[i];

        const expected_checksum = calculateChecksum(std.mem.asBytes(buf[0..25]));
        var data: SaveData = std.mem.bytesToValue(SaveData, &buf);

        if (!std.mem.eql(u8, &data.magic, EXPECTED_SAVE_MAGIC) or expected_checksum != data.checksum or SAVE_VERSION != data.version) {
            // corrupted or missing save
            data = .{
                .magic = EXPECTED_SAVE_MAGIC.*,
                .scores = @splat(0),
                .version = SAVE_VERSION,
                .checksum = 0,
            };
        }

        return data;
    }

    pub fn save(self: *SaveData) void {
        const bytes = std.mem.asBytes(self);
        self.checksum = calculateChecksum(std.mem.asBytes(bytes[0..25]));
        for (bytes, 0..) |b, i| gba.mem.sram[i] = b;
    }
};

const GamePiece = struct {
    piece_type: u4,
    x: i16,
    y: i16,
    rotation: u4,

    fn init(piece_type: u4, rotation: u4) GamePiece {
        const min_x = piece_bounds[piece_type][rotation][0][0];
        const max_x = piece_bounds[piece_type][rotation][1][0];

        const piece_width: u8 = @intCast(max_x - min_x);

        const x: i16 = (GRID_WIDTH / 2) - (piece_width / 2);

        const min_y = @as(i16, piece_bounds[piece_type][rotation][0][1]);
        const y: i16 = 0 - min_y;

        return .{.piece_type = piece_type, .x = x, .y = y, .rotation = rotation };
    }

    fn canMoveRight(self: *GamePiece, grid: *Grid) bool {
        return grid.fits(self.piece_type, self.rotation, self.x + 1, self.y);
    }

    fn canMoveLeft(self: *GamePiece, grid: *Grid) bool {
        return grid.fits(self.piece_type, self.rotation, self.x - 1, self.y);
    }

    fn canMoveDown(self: *GamePiece, grid: *Grid) bool {
        return grid.fits(self.piece_type, self.rotation, self.x, self.y + 1);
    }

    fn isGrounded(self: *GamePiece, grid: *Grid) bool {
        return !self.canMoveDown(grid);
    }

    pub fn attemptMoveLeft(self: *GamePiece, grid: *Grid) bool {
        if (self.canMoveLeft(grid)) {
            self.x -= 1;
            return true;
        }
        return false;
    }

    pub fn attemptShift(self: *GamePiece, grid: *Grid, direction: i2) bool {
        var successful = false;
        if (direction == 1) {
            successful = self.attemptMoveRight(grid);
        } else if (direction == -1) {
            successful = self.attemptMoveLeft(grid);
        }
        return successful;
    }

    pub fn attemptMoveRight(self: *GamePiece, grid: *Grid) bool {
        if (self.canMoveRight(grid)) {
            self.x += 1;
            return true;
        }
        return false;
    }

    pub fn attemptMoveDown(self: *GamePiece, grid: *Grid) bool {
        if (self.canMoveDown(grid)) {
            self.y += 1;
            return true;
        } else {
            return false;
        }
    }

    pub fn attemptRotateClockwise(self: *GamePiece, grid: *Grid) bool {
        const new_rotation = (self.rotation +% 1) % 4;
        if (grid.fits(self.piece_type, new_rotation, self.x, self.y)) {
            self.rotation = new_rotation;
            return true;
        }
        return false;
    }

    pub fn attemptRotateCounterclockwise(self: *GamePiece, grid: *Grid) bool {
        const new_rotation = (self.rotation -% 1) % 4;
        if (grid.fits(self.piece_type, new_rotation, self.x, self.y)) {
            self.rotation = new_rotation;
            return true;
        }
        return false;
    }

    fn hide(self: *GamePiece, oam: *ShadowOAM) void {
        const first_object = @as(u16, self.piece_type) * 4; // 4 blocks per self
        for (0..4) |i| {
            oam[first_object + i].mode = .hidden;
        }
    }

    fn draw(self: *GamePiece, oam: *ShadowOAM) void {
        const first_object = @as(u16, self.piece_type) * 4; // 4 blocks per self
        for (pieces[self.piece_type].cells[self.rotation], 0..) |cell, i| {
            const local_cell_x = self.x + cell[0];
            const local_cell_y = self.y + cell[1];

            const grid_x: i16 = gridX(self.x);
            const grid_y: i16 = gridY(self.y);
            const should_render = local_cell_x >= 0 and local_cell_x < GRID_WIDTH and local_cell_y >= 0 and local_cell_y < GRID_HEIGHT and grid_x >= 0 and grid_y >= 0;
            
            if (should_render) {
                const casted_grid_x: u9 = @intCast(grid_x);
                const casted_grid_y: u8 = @intCast(grid_y);

                oam[first_object + i] = .init(.{
                    .x = casted_grid_x + @as(u9, cell[0]) * block_size,
                    .y = casted_grid_y + @as(u8, cell[1]) * block_size,
                    .base_tile = 0,
                    .palette = self.piece_type,
                });
            } else {
                oam[first_object + i].mode = .hidden;
            }
        }
    }
};

const grid_x_start: i16 = @intCast((gba.display.screen_width_tiles - GRID_WIDTH) / 2);
const grid_y_start: i16 = @intCast((gba.display.screen_height_tiles - GRID_HEIGHT) / 2);

const GameState = enum(u2) {
    playing,
    clearing_line,
    game_over,
    //paused,
    //menu,
};

const InputState = struct {
    input: gba.input.BufferedKeysState = .{},
    das_dir: i2 = 0,
    das_frames: u8 = 0,
};

const LockState = struct {
    frames: u8 = 0,
    resets: u8 = 0,
    lowest_y: i16 = 0,
};

const AnimationState = struct {
    frames_left: u32 = 0,
};

const text_charblock = 1;    // charblock 0 holds your block tile; keep text separate
const text_first_tile = 1;   // tile 0 stays blank = transparent everywhere else
const text_palette = 15;

const TextBox = struct {
    x: u5,
    y: u5,
    w: u6,
    h: u6,

    map: gba.display.BackgroundMap,

    fn init(map: gba.display.BackgroundMap, x: u5, y: u5, w: u6, h: u6) TextBox {
        map.getBaseScreenblock().fillRectLinear(
            .{ .tile = text_first_tile, .palette = text_palette },
            x, y, w, h,
        );

        return .{
            .x = x,
            .y = y,
            .w = w,
            .h = h,
            .map = map,
        };
    }

    fn surface(self: *TextBox) gba.image.SurfaceTiles4BppVram {
        return gba.display.bg_blocks.getSurface4Bpp(
            text_charblock * 512 + text_first_tile,
            self.w,
            self.h,
        );
    }
};

const Game = struct {
    state: GameState = .playing,
    frame_counter: u32 = 0x100,
    gravity_frames: u8 = 0,
    save_data: SaveData,
    score: u32 = 0,
    input_state: InputState = .{},
    animation_state: AnimationState = .{},
    lock_state: LockState = .{},
    grid: Grid,
    shadow_oam: ShadowOAM,
    grid_map: gba.display.BackgroundMap,
    background_map: gba.display.BackgroundMap,
    current_piece: ?GamePiece,
    score_text: TextBox,

    fn setupText() gba.display.BackgroundMap {
        gba.display.bg_palette.banks[text_palette][1] = .white;

        const background_map = gba.display.BackgroundMap.setup(0, .{
            .base_charblock = text_charblock,
            .base_screenblock = 30,
            .size = .size_32x32,
        });

        background_map.getBaseScreenblock().fillRect(.{}, 0, 0, 32, 32);
        return background_map;
    }

    fn recordHighScore(self: *Game) void {
        const scores = &self.save_data.scores;

        const slot = for (scores, 0..) |s, i| {
            if (self.score > s) break i;
        } else return;

        var i: usize = scores.len - 1;
        while (i > slot) : (i -= 1) {
            scores[i] = scores[i - 1];
        }

        scores[slot] = self.score;
        self.save_data.save();
    }

    fn addScore(self: *Game, plus: u32) void {
        self.score += plus;
        self.drawScore(self.score);
    }

    fn drawScore(self: *Game, score: u32) void {
        var buf: [11]u8 = undefined;
        const len = gba.format.formatDecimalI32(&buf, @intCast(score), .{});

        const s = self.score_text.surface();
        s.draw().fill(0);    // text() only sets pixels, so erase first
        s.draw().text("SCORE", .init(1), .{ .x = 0, .y = 0 });
        s.draw().text(buf[0..len], .init(1), .{ .x = 0, .y = 14 });
    }

    fn spawnPiece(self: *Game) void {
        if (self.current_piece) |*piece| {
            piece.hide(&self.shadow_oam);
        }

        var current_piece: GamePiece = .init(
            @intCast(random.qran_range(0, 6)),
            @intCast(random.qran_range(0, 3)),
        );

        if (!self.grid.fits(current_piece.piece_type, current_piece.rotation, current_piece.x, current_piece.y)) {
            self.state = .game_over;
            self.recordHighScore();
            return;
        }

        self.gravity_frames = 0;
        current_piece.draw(&self.shadow_oam);
        self.current_piece = current_piece;

        self.lock_state = .{};
    }

    fn reset(self: *Game) void {
        var grid: Grid = .init();
        if (@import("builtin").mode == .debug) {
            grid.setDebugScenario(.two_non_consecutive_lines);
        }

        var grid_map = gba.display.BackgroundMap.setup(1, .{
            .base_screenblock = 31,
            .size = .size_32x32,
        });

        grid_map.getBaseScreenblock().fillRect(.{ .tile = 1, .palette = 7 }, grid_x_start, grid_y_start, GRID_WIDTH, GRID_HEIGHT);

        grid.reRenderFrozenPieces(&grid_map);

        const background_map = setupText();

        const save_data = self.save_data;

        self.* = .{
            .grid = grid,
            .shadow_oam = @splat(.{ .mode = .hidden }),
            .grid_map = grid_map,
            .current_piece = null,
            .background_map = background_map,
            .save_data = save_data,
            .score_text = .init(
                background_map,
                4,
                1,
                8,
                4,
            )
        };
    }

    fn init() Game {
        gba.display.status.vblank_interrupt = true;
        gba.interrupt.enable.vblank = true;
        gba.interrupt.master.enable = true;

        gba.display.hideAllObjects();
        loadSpriteData();

        gba.display.ctrl.* = .initMode0(.{
            .obj_mapping = .map_1d,
            .obj = true,
            .bg0 = true,
            .bg1 = true,
        });

        var game: Game = undefined;
        game.save_data = SaveData.load();
        game.reset();
        game.drawScore(game.score);
        return game;
    }

    fn saveHighScores(self: *Game) void {
        self.save_data.save();
    }

    fn lock(self: *Game) void {
        const piece = &self.current_piece.?;
        self.grid.freezePiece(piece.piece_type, piece.rotation, piece.x, piece.y);
        self.grid.reRenderFrozenPieces(&self.grid_map);
        piece.hide(&self.shadow_oam);
        self.current_piece = null;

        const full_line_count = self.grid.getFullLines();
        if (full_line_count > 0) {
            self.state = .clearing_line;

            // each line takes 100ms = 1/10th of 60fps = 6 frames
            self.animation_state.frames_left = full_line_count * 6;
        } else {
            self.spawnPiece();
        }

    }
};

pub export fn main() void {
    var game: Game = .init();

    game.spawnPiece();

    while (true) : (game.frame_counter +%= 1) {
        gba.bios.vblankIntrWait();

        game.input_state.input.poll();

        const dir = game.input_state.input.getAxisHorizontal();

        const dir_changed = dir != game.input_state.das_dir;

        if (dir_changed) { // new press, released, or reversed
            game.input_state.das_dir = dir;
            game.input_state.das_frames = 0;
        }

        switch(game.state) {
            .game_over => {
                if (game.input_state.input.isJustPressed(.start)) {
                    game.reset();
                    game.spawnPiece();
                }
            },
            .clearing_line => {
                //game.animation_state.frames_left -= 1;
                // TODO: remove this and actually animate it
                game.animation_state.frames_left = 0;

                if (game.animation_state.frames_left == 0) {
                    game.state = .playing;

                    const lines_cleared = game.grid.getFullLines();
                    game.addScore(15 * lines_cleared * lines_cleared);

                    game.grid.deleteFullLines();
                    game.grid.reRenderFrozenPieces(&game.grid_map);

                    game.spawnPiece();
                }
            },
            .playing => {
                var moved = false;
                if (dir_changed and dir != 0) {
                    moved = game.current_piece.?.attemptShift(&game.grid, dir);
                } else if (dir != 0) {
                    game.input_state.das_frames += 1;
                    if (game.input_state.das_frames == DAS_FRAMES) {
                        moved = game.current_piece.?.attemptShift(&game.grid, dir);
                        game.input_state.das_frames = DAS_FRAMES - ARR_FRAMES;
                    }
                }

                if (game.input_state.input.isJustPressed(.A)) {
                    if (game.current_piece.?.attemptRotateClockwise(&game.grid)) {
                        moved = true;
                    }
                } else if (game.input_state.input.isJustPressed(.B)) {
                    if (game.current_piece.?.attemptRotateCounterclockwise(&game.grid)) {
                        moved = true;
                    }
                }

                if (moved) {
                    if (game.lock_state.resets < MAX_LOCK_RESETS) {
                        game.lock_state.frames = 0;
                        game.lock_state.resets += 1;
                    }
                }

                if (game.current_piece.?.isGrounded(&game.grid)) {
                    game.lock_state.frames += 1;
                    if (game.lock_state.frames == LOCK_DELAY_FRAMES) {
                        game.lock_state.frames = 0;
                        game.lock();
                    }

                } else {
                    game.lock_state.frames = 0;

                    const reference_gravity: u16 = if (game.input_state.input.isPressed(.down)) SOFT_DROP_FRAMES else GRAVITY_FRAMES;

                    game.gravity_frames += 1;

                    if (game.gravity_frames >= reference_gravity) {
                        game.gravity_frames = 0;
                        _ = game.current_piece.?.attemptMoveDown(&game.grid);
                        const new_low = game.current_piece.?.y;
                        if (new_low > game.lock_state.lowest_y) {
                            game.lock_state.resets = 0;
                            game.lock_state.frames = 0;
                        }
                        game.lock_state.lowest_y = new_low;
                    }
                }

                if (game.current_piece) |*piece| {
                    piece.draw(&game.shadow_oam);
                }
            }
        }

        gba.mem.memcpy32(gba.display.objects, &game.shadow_oam, @sizeOf(ShadowOAM) / 4);
    }
}
