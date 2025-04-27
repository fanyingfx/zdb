const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("editline.h");
});

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    c.rl_initialize();
    _ = c.read_history("/home/fan/.zig_shell_history");
    while (true) {
        // Read line with libedit
        const input = c.readline("$ ");
        if (input == null) {
            try stdout.print("\n", .{});
            break; // EOF (Ctrl+D)
        }
        defer std.c.free(@ptrCast(input));

        const line = std.mem.span(input);
        if (line.len == 0) continue;

        // Add to history
        _ = c.add_history(input);

        // Trim whitespace
        const trimmed = std.mem.trim(u8, line, " \t\n");
        if (std.mem.eql(u8, trimmed, "exit")) break;

        // Execute command
        try stdout.print("Executing: {s}\n", .{trimmed});
        try executeCommand(allocator, trimmed);
        // c.rl_save_prompt();

        // Save history
    }
    // const status = c.write_history("/home/fan/.zig_shell_history");
    // std.debug.print("status:{}\n", .{status});

}

fn executeCommand(allocator: std.mem.Allocator, command: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    // Split command into arguments
    var it = std.mem.splitAny(u8, command, " ");
    while (it.next()) |arg| {
        try args.append(arg);
    }

    if (args.items.len == 0) return;

    // Run the command
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = args.items,
    }) catch |err| {
        try stdout.print("Error executing '{s}': {s}\n", .{ command, @errorName(err) });
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        try stdout.print("{s}", .{result.stdout});
    }
    if (result.stderr.len > 0) {
        try stdout.print("{s}", .{result.stderr});
    }
}
