const std = @import("std");
const Allocator = std.mem.Allocator;
const stringToEnum = std.meta.stringToEnum;
const fatal = std.process.fatal;
const cleanExit = std.process.cleanExit;
const usage =
    \\Usage: cat [OPTION]... [FILE]...
    \\Concatenate FILE(s) to standard output.
    \\With no FILE, or when FILE is -, read standard input.
    \\
    \\-b number nonempty output lines, overrides
    \\-n number all output lines
;

const Option = enum { n, b };
var opts = struct {
    n: bool = false,
    b: bool = false,
}{};

pub fn main(init: std.process.Init) anyerror!void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len <= 1) {
        const stdin_buffer = try allocator.alloc(u8, 4096);
        defer allocator.free(stdin_buffer);
        var stdin_reader = std.Io.File.stdin().reader(io, stdin_buffer);
        const stdin = &stdin_reader.interface;

        const stdout_buffer = try allocator.alloc(u8, 4096);
        defer allocator.free(stdout_buffer);
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer);
        const stdout = &stdout_writer.interface;

        while (true) {
            const line = stdin.takeDelimiterInclusive('\n') catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };

            try stdout.writeAll(line);
            try stdout.flush();
        }
    }

    var file_paths: std.ArrayList([]const u8) = .empty;
    for (args[1..]) |arg| {
        if (arg[0] == '-') {
            if (std.mem.eql(u8, arg, "--help")) {
                std.log.info("{s}", .{usage});
                cleanExit(io);
            }

            const opt = stringToEnum(Option, arg[1..]) orelse {
                try file_paths.append(allocator, arg);
                continue;
            };
            switch (opt) {
                inline else => |tag| @field(opts, @tagName(tag)) = true,
            }
        } else {
            try file_paths.append(allocator, arg);
        }
    }

    if (file_paths.items.len <= 0) {
        std.log.info("{s}", .{usage});
        fatal("expected files", .{});
    }

    const num_files = file_paths.items.len;
    const files = try allocator.alloc(std.Io.File, num_files);
    defer {
        for (files) |file| file.close(io);
        allocator.free(files);
    }
    const file_sizes = try allocator.alloc(usize, num_files);
    defer allocator.free(file_sizes);

    var total_files_size: usize = 0;

    const cwd = std.Io.Dir.cwd();
    for (file_paths.items, 0..) |file_path, i| {
        files[i] = cwd.openFile(io, file_path, .{}) catch |err| {
            fatal("{s}: {s}", .{ file_path, @errorName(err) });
        };
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

    const noOptions = file_paths.items.len == args.len - 1;
    if (noOptions) {
        std.debug.print("{s}", .{buffer});
        return;
    }

    var line_count: usize = 0;
    var extra_size: usize = 0;

    offset = 0;
    for (file_sizes) |size| {
        const file_buf = buffer[offset .. offset + size];
        var start: usize = 0;

        while (std.mem.findScalar(u8, file_buf[start..], '\n')) |i| {
            if (opts.b and i == 0) {
                start += 1;
                continue;
            }
            line_count += 1;
            extra_size += std.fmt.count("{d} ", .{line_count});
            start += i + 1;
        }

        if (start < file_buf.len) {
            if (opts.b) {
                extra_size += 1;
                continue;
            }
            line_count += 1;
            extra_size += std.fmt.count("{d} ", .{line_count});
            extra_size += 1;
        }

        offset += size;
    }

    const output_size = total_files_size + extra_size;
    const output = try allocator.alloc(u8, output_size);
    defer allocator.free(output);

    var out_writer = std.Io.Writer.fixed(output);

    offset = 0;
    line_count = 0;
    for (file_sizes) |size| {
        const file_buf = buffer[offset .. offset + size];
        var start: usize = 0;

        while (std.mem.indexOfScalar(u8, file_buf[start..], '\n')) |i| {
            const line = file_buf[start .. start + i + 1]; // includes '\n'
            if (opts.b and i == 0) {
                try out_writer.print("{s}", .{line});
                start += 1;
                continue;
            }
            line_count += 1;
            try out_writer.print("{d} {s}", .{ line_count, line });
            start += i + 1;
        }

        if (start < file_buf.len) {
            const line = file_buf[start..];
            if (opts.b) {
                try out_writer.print("{s}", .{line});
                continue;
            }
            line_count += 1;
            try out_writer.print("{d} {s}\n", .{ line_count, line });
        }

        offset += size;
    }

    std.debug.print("{s}", .{output});
}
