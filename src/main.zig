const std = @import("std");
const zdb = @import("lib/zdb.zig");
const Linenoise = @import("linenoize").Linenoise;
const linux = std.os.linux;

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.heap.page_allocator.free(args);
    if (args.len == 1) {
        std.debug.panic("No arguments given\n", .{});
    }

    // std.debug.print("{s}\n", .{args[1]});

    var proc = try zdb.attach(args);
    // var status: u32 = 0;
    // const options = 0; // std.os.linux.W.

    // if (std.os.linux.waitpid(pid, &status, options) < 0) {
    //     return error.WaitpidFailed;
    // }
    const allocator = std.heap.page_allocator;

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    while (try ln.linenoise("sdb> ")) |input| {
        var line_str: []const u8 = undefined;
        defer allocator.free(input);
        if (std.mem.eql(u8, input, "")) {
            if (ln.history.hist.items.len > 0) {
                line_str = ln.history.hist.getLast();
            }
        } else {
            line_str = input;
            try ln.history.add(input);
        }
        if (line_str.len > 0) {
            // std.debug.print("{s}\n", .{line_str});
            zdb.handle_command(&proc,line_str);
        }
    }
}

