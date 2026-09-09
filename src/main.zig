const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const seq_clear_line = "\x1b[2K";
const seq_refresh = "\x1b[2J";
const seq_move_forward = "\x1b[2J";

const seq_green = "\x1b[32m";
// const seq_blue = "\x1b[33m";
const seq_red = "\x1b[31m";
const seq_gray = "\x1b[90m";
const seq_bg_yellow = "\x1b[43m";

const seq_hide_cursor = "\x1b[?25l";
const seq_show_cursor = "\x1b[?25h";

const seq_reset = "\x1b[0m";
const seq_bold = "\x1b[22m";

// required width of terminal
const MIN_WIDTH = 90;
// count of lines in challenge
const LINES = 20;
// count of workds in line
const WORDS_IN_LINE = 10;
// length of the challenge
const CHALLENGE_MILLISECONDS = 30_000;

const word_list = @import("words.zig").word_list;

var is_done = false;

const Word = struct {
    str: []const u8,
    typed: [32]u8,
    typed_count: usize,

    pub fn init(str: []const u8) Word {
        return Word{ .str = str, .typed = undefined, .typed_count = 0 };
    }
};

const Challenge = struct {
    lines: [][]Word,
    cur_word: usize, // current word position in line
    cur_line: usize, // current line
    cursor_idx: usize, // cursor for terminal
    time: i64,

    pub fn init(lines: [][]Word) Challenge {
        return Challenge{
            .lines = lines,
            .cur_line = 0,
            .cur_word = 0,
            .cursor_idx = 0,
            .time = 0,
        };
    }
};

var stdout_writer: *std.Io.Writer = undefined;

var io: Io = undefined;

pub fn main(init: std.process.Init) !void {
    io = init.io;
    const arena = init.arena;
    defer arena.deinit();
    // const gpa = init.gpa;
    //
    var log_buf: [2048]u8 = undefined;
    logger = try Logger.init(&log_buf, false);

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

    print("{s}{s}(:3 Type Chimpanzee{s} ESC or Ctrl+C to quit.\n\n\r", .{ seq_bg_yellow, seq_gray, seq_reset });

    var words_buf: [LINES][WORDS_IN_LINE]Word = undefined;
    var lines: [LINES][]Word = undefined;
    try genWords(&lines, &words_buf);

    var c = Challenge.init(&lines);

    const start_ms = getMs();
    var time: i64 = start_ms;

    while (!is_done) {
        const l = c.lines[c.cur_line];
        var w = &l[c.cur_word];

        print("\r{s}", .{seq_hide_cursor});
        if (c.cur_word == 0 and w.typed_count == 0) {
            renderLineInitial(c);
        } else {
            renderLineDiff(c);
        }
        print("\r{s}", .{seq_show_cursor});

        moveCursorForward(c.cursor_idx);

        var bytebuf: [1]u8 = undefined;
        try stdin_reader.readSliceAll(&bytebuf);
        const typed = bytebuf[0];

        if (typed == '\x03' or typed == '\x1b') {
            // ESC or Ctrl+C
            break;
        } else if (typed == '\x08' or typed == '\x7f') {
            //backspace
            if (w.typed_count > 0) {
                w.typed_count -= 1;
                w.typed[w.typed_count] = '\x00';
                c.cursor_idx -= 1;
            } else if (c.cur_word > 0) {
                // spaces between words
                c.cursor_idx -= 2;

                // if the previous word isn't fully typed
                const prev_w = l[c.cur_word - 1];
                if (prev_w.str.len > prev_w.typed_count) {
                    const adjust = prev_w.str.len - prev_w.typed_count;
                    c.cursor_idx -= adjust;
                }

                c.cur_word -= 1;
            }
        } else if (typed == ' ' or typed == '\r') {
            w.typed[w.typed_count + 1] = '\x00';
            if (c.cur_word < l.len - 1) {
                c.cursor_idx += w.str.len + 2 - w.typed_count;
                c.cur_word += 1;
            } else if (c.cur_word == l.len - 1 and c.cur_line < c.lines.len - 1) {
                // next line
                c.cur_line += 1;
                c.cur_word = 0;
                c.cursor_idx = 0;
                // print("\r\n", .{}); // keep old lines
            } else if (c.cur_word == l.len - 1 and c.cur_line == c.lines.len - 1) {
                is_done = true;
            }
        } else if ('a' <= typed and typed <= 'z') {
            if (w.typed_count <= w.str.len) {
                w.typed[w.typed_count] = typed;
                w.typed[w.typed_count + 1] = '\x00';
                w.typed_count += 1;
                c.cursor_idx += 1;
            } else {
                w.typed[w.str.len] = typed;
                w.typed[w.str.len + 1] = '\x00';
            }
        }
        time = getMs() - start_ms;

        if (time > CHALLENGE_MILLISECONDS) {
            is_done = true;
        }
    }

    if (is_done) {
        c.time = time;
        showResult(c);
        try io.sleep(.fromSeconds(1), .awake);
    } else {
        print("\n\rBye!!\n", .{});
    }
}

// print all lines first
fn renderLineInitial(c: Challenge) void {
    // initial render
    print("\r{s}", .{seq_clear_line});

    const line = c.lines[c.cur_line];
    for (line) |w| {
        renderWord(w);

        print(" ", .{});
    }

    print("\r", .{});
}

fn renderLineDiff(c: Challenge) void {
    print("\r", .{});

    const line = c.lines[c.cur_line];
    for (line, 0..) |w, i| {
        if (i < c.cur_word) {
            moveCursorForward(w.str.len + 2);
        } else if (i == c.cur_word) {
            logger.log("print", .{});
            renderWord(w);
            print(" ", .{});
        }
    }

    print("\r", .{});
}

fn renderWord(word: Word) void {
    // mock delays in slower PC
    // io.sleep(.fromMilliseconds(20), .awake) catch {};
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

fn genWords(lines: [][]Word, words_buf: [][WORDS_IN_LINE]Word) !void {
    var r: std.Random.IoSource = .{ .io = io };

    for (0..LINES) |i| {
        for (0..WORDS_IN_LINE) |j| {
            const random = r.interface().uintAtMost(usize, word_list.len - 1);

            words_buf[i][j] = Word.init(word_list[random]);
        }

        lines[i] = &words_buf[i];
    }
}

fn checkWinSize() !void {
    const posix = std.posix;
    var ws: std.posix.winsize = undefined;

    // Perform the ioctl call on stdout
    const err = posix.system.ioctl(posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));

    if (posix.errno(err) == .SUCCESS) {
        // std.debug.print("Width: {d}, Height: {d}\n", .{ ws.ws_col, ws.ws_row });
        if (ws.col < MIN_WIDTH) {
            std.debug.print("The terminal size is too narrow to play this.\n", .{});
            return error.WinSizeTooSmall;
        }
    } else {
        std.debug.print("Failed to get terminal size.\n", .{});
        return error.FailedToGetWinSize;
    }
}

fn showResult(c: Challenge) void {
    var correct: usize = 0;
    var mistakes: usize = 0;

    for (c.lines) |l| {
        for (l) |w| {
            for (w.typed, 0..) |t, i| {
                if (w.typed_count == 0) continue;

                if (t == '\x00') continue;

                if (i < w.str.len) {
                    if (t == w.str[i]) {
                        correct += 1;
                    } else {
                        mistakes += 1;
                    }
                }
            }
        }
    }

    var accuracy: usize = 0;
    const typed = correct + mistakes;
    if (typed > 0) {
        accuracy = 100 * correct / typed;
    }

    print("\n\r{s}Accuracy:{s} {d}% (Correct: {d} Mistakes: {d})", .{ seq_green, seq_reset, accuracy, correct, mistakes });

    const wpm: usize = @intCast(60_000 * typed / 5 / @as(u64, @intCast(c.time)));

    print("\n\r{s}WPM:{s}      {d}\r\n", .{ seq_green, seq_reset, wpm });
}

fn getMs() i64 {
    return Io.Clock.now(.awake, io).toMilliseconds();
}

var f_writer: Io.File.Writer = undefined;
var logger: Logger = undefined;

const Logger = struct {
    writer: *Io.Writer,
    enabled: bool,

    fn init(buf: []u8, enabled: bool) !Logger {
        const f = try std.Io.Dir.cwd().openFile(io, "./tc.log", .{ .mode = .write_only });
        f_writer = f.writer(io, buf);

        return Logger{ .writer = &f_writer.interface, .enabled = enabled };
    }

    fn log(l: *Logger, comptime fmt: []const u8, args: anytype) void {
        if (!l.enabled) return;

        l.log_inner(fmt, args) catch |e| {
            std.debug.print("log failed: {}", .{e});
        };
    }

    fn log_inner(l: *Logger, comptime fmt: []const u8, args: anytype) !void {
        try l.writer.print(fmt, args);
        try l.writer.print("\n", .{});
        try l.writer.flush();
    }
};
