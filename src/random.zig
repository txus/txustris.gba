const std = @import("std");

var __qran_seed: i32 = 42;

pub fn sqran(seed: i32) i32 {
    const old: i32 = __qran_seed;
    __qran_seed = seed;
    return old;
}

pub inline fn qran() i32
{
    __qran_seed= 1664525*%__qran_seed+%1013904223;
    return (__qran_seed>>16) & 0x7FFF;
}

pub inline fn qran_range(min: i32, max: i32) i32 {
    return (qran()*(max-min)>>15)+min;
}

/// 7-bag randomizer
pub const Bag = struct {
    pieces: [7]u4 = undefined,
    index: u8 = 7,

    pub fn next(self: *Bag) u4 {
        if (self.index == self.pieces.len) self.refill();
        const piece = self.pieces[self.index];
        self.index += 1;
        return piece;
    }

    fn refill(self: *Bag) void {
        for (&self.pieces, 0..) |*p, i| p.* = @intCast(i);

        // fisher–yates: from the end, swap each slot with a random slot at or before it.
        var i: usize = self.pieces.len - 1;
        while (i > 0) : (i -= 1) {
            const j: usize = @intCast(qran_range(0, @intCast(i + 1)));
            std.mem.swap(u4, &self.pieces[i], &self.pieces[j]);
        }
        self.index = 0;
    }
};
