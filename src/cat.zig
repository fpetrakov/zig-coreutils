const std = @import("std");
const stringToEnum = std.meta.stringToEnum;

const fatal = std.process.fatal;
const usage =
    \\Usage: cat [OPTION]... [FILE]...
    \\Concatenate FILE(s) to standard output.
;

const Option = enum {
    @"-n",
};

pub fn main(init: std.process.Init) anyerror!void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len <= 1) {
        std.log.info("{s}", .{usage});
        fatal("expected command argument", .{});
    }

    var file_paths: std.ArrayList([]const u8) = .empty;
    var n = false;

    for (args[1..]) |arg| {
        const opt = stringToEnum(Option, arg) orelse {
            try file_paths.append(allocator, arg);
            continue;
        };
        switch (opt) {
            .@"-n" => n = true,
        }
    }

    if (file_paths.items.len <= 0) {
        // TODO: read stdin to stdout
        std.log.info("{s}", .{usage});
        fatal("expected files", .{});
    }

    const num_files = file_paths.items.len;
    const files = try allocator.alloc(std.Io.File, num_files);
    defer {
        for (files) |file| file.close();
        allocator.free(files);
    }
    const file_sizes = try allocator.alloc(usize, num_files);
    defer allocator.free(file_sizes);

    var total_files_size: usize = 0;

    const cwd = std.Io.Dir.cwd();
    for (file_paths.items, 0..) |file_path, i| {
        files[i] = try cwd.openFile(io, file_path, .{});
        const stat = try files[i].stat(io);
        file_sizes[i] = @intCast(stat.size);
        total_files_size += file_sizes[i];
    }

    const buffer = try allocator.alloc(u8, total_files_size);
    defer allocator.free(buffer);

    var offset: usize = 0;
    for (files, file_sizes) |file, size| {
        _ = try file.readPositionalAll(io, buffer[offset .. offset + size], 0);
        offset += size;
    }

    std.debug.print("{s}", .{buffer});
}
