const std = @import("std");
const Allocator = std.mem.Allocator;
const stringToEnum = std.meta.stringToEnum;
const fatal = std.process.fatal;
const cleanExit = std.process.cleanExit;
const usage =
    \\Usage: touch [OPTION]... [FILE]...
    \\Concatenate FILE(s) to standard output.
;

const Option = enum {
    @"-n",
};

pub fn main(init: std.process.Init) anyerror!void {
    const io = init.io;
}
