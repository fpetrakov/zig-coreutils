const std = @import("std");
const Allocator = std.mem.Allocator;
const stringToEnum = std.meta.stringToEnum;
const fatal = std.process.fatal;
const cleanExit = std.process.cleanExit;
const mem = std.mem;
const Io = std.Io;
const usage =
    \\Usage: touch [OPTION]... [FILE]...
    \\Update the access and modification times of each FILE to the current time.
    \\A FILE argument that does not exist is created empty, unless -c or -h is supplied.
    \\A FILE argument string of - is handled specially and causes touch to
    \\change the times of the file associated with standard output.
    \\
    \\-a change only the access time
;

const Option = enum {
    a,
};
var opts = struct {
    a: bool = false,
}{};

pub fn main(init: std.process.Init) anyerror!void {
    const io = init.io;
    const arena = init.arena.allocator();

    var args_it = try init.minimal.args.iterateAllocator(arena);
    if (!args_it.skip()) fatal("missing argv[0]", .{});

    var file_paths: std.ArrayList([]const u8) = .empty;
    while (args_it.next()) |arg| {
        if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                std.log.info("{s}", .{usage});
                cleanExit(io);
            }

            const opt = stringToEnum(Option, arg[1..]) orelse {
                try file_paths.append(arena, arg);
                continue;
            };

            switch (opt) {
                inline else => |tag| @field(opts, @tagName(tag)) = true,
            }
        } else {
            try file_paths.append(arena, arg);
        }
    }

    const num_files = file_paths.items.len;
    if (num_files <= 0) {
        std.log.info("{s}", .{usage});
        fatal("expected files", .{});
    }

    const cwd = Io.Dir.cwd();
    for (file_paths.items) |file_path| {
        cwd.access(io, file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                var file = try cwd.createFile(io, file_path, .{});
                defer file.close(io);
                continue;
            },
            else => return err,
        };

        var file = try cwd.openFile(io, file_path, .{ .mode = .read_write });
        defer file.close(io);

        if (opts.a) {
            _ = try io.vtable.fileSetTimestamps(io.userdata, file, .{
                .access_timestamp = .now,
            });
            continue;
        }

        try file.setTimestampsNow(io);
    }
}
