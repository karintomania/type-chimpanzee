const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const cwd = std.Io.Dir.cwd();

    const f = try cwd.openFile(io, "./gistfile1.txt", .{ .mode = .read_only });
    var buf: [4098]u8 = undefined;
    var f_reader = f.reader(io, &buf);
    const reader = &f_reader.interface;

    while (try reader.takeDelimiter('\n')) |line| {
        if (line.len == 0) {
            break;
        }

        var itr = std.mem.tokenizeScalar(u8, line, '\t');

        const w = itr.next().?;

        // filter 1 char words
        if (w.len > 1) std.debug.print("{s}\n", .{w});
    }
}
