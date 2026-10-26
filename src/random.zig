var __qran_seed: i32 = 42;

fn sqran(seed: i32) i32 {
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
