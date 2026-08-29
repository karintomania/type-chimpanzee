const std = @import("std");

const Allocator = std.mem.Allocator;

const seq_clear_line = "\x1b[2K";
const seq_refresh = "\x1b[2J";
const seq_move_forward = "\x1b[2J";
// const seq_green = "\x1b[32m";
const seq_red = "\x1b[31m";
const seq_gray = "\x1b[90m";
const seq_reset = "\x1b[0m";

const Word = struct {
    str: []const u8,
    typed: [32]u8,
    typed_count: usize,

    pub fn init(str: []const u8) Word {
        return Word{ .str = str, .typed = undefined, .typed_count = 0 };
    }
};

const Challenge = struct {
    words: []Word,
    index: usize,
    cursor_idx: usize,
};

var stdout_writer: *std.Io.Writer = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena;
    defer arena.deinit();
    // const gpa = init.gpa;

    checkWinSize() catch |e| switch (e) {
        error.WinSizeTooSmall => std.process.exit(1),
        else => return e,
    };

    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);
    stdout_writer = &stdout.interface;

    var buf: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &buf);
    const stdin_reader = &stdin.interface;

    try enableRawMode();
    defer disableRawMode();

    print("ESC or Ctrl+C to quit.\n\r", .{});

    var words: [10]Word = undefined;
    try genWords(init.io, &words);

    var c = Challenge{
        .words = &words,
        .index = 0,
        .cursor_idx = 0,
    };

    while (true) {
        renderLine(c);
        moveCursorForward(c.cursor_idx);

        var t = &c.words[c.index];
        var bytebuf: [1]u8 = undefined;
        try stdin_reader.readSliceAll(&bytebuf);
        const typed = bytebuf[0];

        if (typed == '\x03' or typed == '\x1b') {
            // ESC or Ctrl+C
            break;
        } else if (typed == '\x08' or typed == '\x7f') {
            //backspace
            if (t.typed_count > 0) {
                t.typed_count -= 1;
                t.typed[t.typed_count] = '\x00';
                c.cursor_idx -= 1;
            } else if (c.index > 0) {
                c.index -= 1;
                c.cursor_idx -= 2;
            }

            continue;
        } else if (typed == ' ' and c.index < c.words.len - 1) {
            c.cursor_idx += t.str.len + 2 - t.typed_count;
            c.index += 1;
            continue;
        } else if ('a' <= typed and typed <= 'z') {
            if (t.typed_count <= t.str.len) {
                t.typed[t.typed_count] = typed;
                t.typed[t.typed_count + 1] = '\x00';
                t.typed_count += 1;
                c.cursor_idx += 1;
            } else {
                t.typed[t.str.len] = typed;
                t.typed[t.str.len + 1] = '\x00';
            }
        }
    }
}

fn renderLine(c: Challenge) void {
    print("\r{s}", .{seq_clear_line});
    for (c.words, 0..) |w, i| {
        renderWord(w);

        if (c.words.len + 1 != i) {
            print(" ", .{});
        }
    }

    print("\r", .{});
}

fn renderWord(word: Word) void {
    for (word.str, 0..) |c, i| {
        if (i < word.typed_count) {
            if (c == word.typed[i]) {
                print("{s}{c}{s}", .{ seq_gray, c, seq_reset });
            } else {
                print("{s}{c}{s}", .{ seq_red, c, seq_reset });
            }
        } else {
            print("{c}", .{c});
        }
    }

    if (word.typed_count > word.str.len) {
        // print wrong chars after word
        print("{s}{c}{s}", .{ seq_red, word.typed[word.str.len], seq_reset });
    } else {
        print(" ", .{});
    }
}

// pub fn moveCursor(row: u8, col: u8) void {
//     _ = row;
//     // print("\x1b[{d};{d}H", .{ row, col });
//     print("\x1b[;{d}H", .{col});
// }

pub fn moveCursorForward(n: usize) void {
    if (n > 0) {
        print("\x1b[{d}C", .{n});
    }
}

fn print(comptime fmt: []const u8, args: anytype) void {
    stdout_writer.print(fmt, args) catch |e| {
        std.debug.print("{}", .{e});
    };

    stdout_writer.flush() catch |e| {
        std.debug.print("{}", .{e});
    };
}

var original_termios: std.posix.termios = undefined;

pub fn enableRawMode() !void {
    const stdin_fd = std.posix.STDIN_FILENO;
    original_termios = try std.posix.tcgetattr(stdin_fd);

    var raw = original_termios;

    // disable legacy flags
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;

    // disable \r translation to \n
    raw.iflag.ICRNL = false;

    // disable flow control (Ctrl+S, Ctrl+S)
    raw.iflag.ICRNL = false;

    // disable output post-processing
    raw.oflag.OPOST = false;

    // disable echo/canonical mode/signal/extendend input processing
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;

    // Set min read requirements (1 byte at a time, no timeout)
    raw.cc[@intFromEnum(std.posix.system.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.system.V.TIME)] = 0;

    try std.posix.tcsetattr(stdin_fd, .FLUSH, raw);
}

pub fn disableRawMode() void {
    std.posix.tcsetattr(
        std.posix.STDIN_FILENO,
        .FLUSH,
        original_termios,
    ) catch {};
}

fn genWords(io: std.Io, words: []Word) !void {
    var r: std.Random.IoSource = .{ .io = io };

    for (0..words.len) |i| {
        const random = r.interface().uintAtMost(usize, word_list.len - 1);

        words[i].str = word_list[random];
        words[i].typed = undefined;
        words[i].typed_count = 0;
    }
}

const word_list = [_][]const u8{
    "test",
    "word",
    "keyboard",
    "and",
    "otherwise",
};

fn checkWinSize() !void {
    const posix = std.posix;
    var ws: std.posix.winsize = undefined;

    // Perform the ioctl call on stdout
    const err = posix.system.ioctl(posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));

    if (posix.errno(err) == .SUCCESS) {
        // std.debug.print("Width: {d}, Height: {d}\n", .{ ws.ws_col, ws.ws_row });
        if (ws.col < 90) {
            std.debug.print("The terminal size is too narrow to play this.\n", .{});
            return error.WinSizeTooSmall;
        }
    } else {
        std.debug.print("Failed to get terminal size.\n", .{});
        return error.FailedToGetWinSize;
    }
}
