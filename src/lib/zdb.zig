const std = @import("std");
const linux = std.os.linux;
const Process = @import("process.zig").Process;
const print_stop_reason = @import("process.zig").print_stop_reason;

pub fn attach(args: [][:0]u8) !Process {
    if (args.len == 3 and std.mem.eql(u8, args[1], "-p")) {
        const pid = try std.fmt.parseInt(linux.pid_t, args[2], 10);

        std.debug.print("attached to {d}\n", .{pid});
        return Process.attach(pid);
    } else {
        const program_path = args[1];
        return Process.launch(program_path);
    }
}
pub fn handle_command(proc: *Process, line: []const u8) void {
    var argIter = std.mem.splitScalar(u8, line, ' ');
    const command = argIter.next().?;
    if (is_prefix(command, "continue")) {
        std.log.info("start resume {d}\n", .{proc.pid});
        proc.resume_process();
        const reason = proc.wait_on_signal();
        print_stop_reason(proc, reason);
    } else {
        std.debug.panic("Unknown command\n", .{});
    }
}
fn is_prefix(str: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, str, prefix);
}
