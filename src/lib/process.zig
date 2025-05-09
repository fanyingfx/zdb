const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;
const Pipe = @import("pipe.zig").Pipe;
const ProcessState = enum { Stopped, Running, Exited, Terminated };
const Err = error{ ExecError, ForkFailed };
const StopReason = struct {
    reason: ProcessState,
    info: u32,
    pub fn init(wait_status: u32) StopReason {
        var stop_reason: StopReason = undefined;
        if (posix.W.IFEXITED(wait_status)) {
            stop_reason.reason = .Exited;
            stop_reason.info = posix.W.EXITSTATUS(wait_status);
        } else if (posix.W.IFSIGNALED(wait_status)) {
            stop_reason.reason = .Terminated;
            stop_reason.info = posix.W.TERMSIG(wait_status);
        } else if (posix.W.IFSTOPPED(wait_status)) {
            stop_reason.reason = .Stopped;
            stop_reason.info = posix.W.STOPSIG(wait_status);
        }
        return stop_reason;
    }
};
pub const Process = struct {
    is_attached: bool,
    pid: posix.pid_t = 0,
    terminate_on_end_: bool = true,
    state: ProcessState = .Stopped,

    pub fn init(pid: posix.pid_t, terminater_on_end: bool, is_attached: bool) Process {
        return .{ .pid = pid, .terminate_on_end_ = terminater_on_end, .is_attached = is_attached };
    }
    pub fn deinit(proc: Process) void {
        if (proc.pid != 0) {
            // var status:usize=undefined;
            if (proc.is_attached) {
                if (proc.state == .Running) {
                    posix.kill(proc.pid, linux.SIG.STOP) catch unreachable;
                    _ = posix.waitpid(proc.pid, 0);
                }
                posix.ptrace(linux.PTRACE.DETACH, proc.pid, 0, 0) catch unreachable;
                posix.kill(proc.pid, linux.SIG.CONT) catch unreachable;
            }
            if (proc.terminate_on_end_) {
                posix.kill(proc.pid, linux.SIG.KILL) catch unreachable;
                _ = posix.waitpid(proc.pid, 0);
            }
        }
    }

    pub fn launch(path: [*:0]const u8, debug: bool) !Process {
        var channel_buf: [1024]u8 = undefined;
        var channel: Pipe = try .init(true);
        defer channel.deinit();
        const pid: posix.pid_t = try posix.fork();
        // if (pid < 0) {
        //     return error.ForkFailed;
        // }
        if (pid == 0) {
            channel.close_read();
            if (debug) {
                posix.ptrace(linux.PTRACE.TRACEME, 0, 0, 0) catch {
                    exit_and_set_error(&channel, Err.ForkFailed);
                };
            }
            std.posix.execvpeZ(path, &.{null}, &.{null}) catch {
                exit_and_set_error(&channel, Err.ExecError);
            };
        }
        channel.close_write();
        const data = try channel.read(&channel_buf);
        channel.close_read();
        if (data.len > 0) {
            _ = std.posix.waitpid(pid, 0);
            const err = @errorFromInt(data[0]);
            return err;
        }
        var proc: Process = .init(pid, true, debug);
        if (debug) {
            _ = proc.wait_on_signal();
        }
        return proc;
    }
    pub fn attach(pid: linux.pid_t) !Process {
        if (pid <= 0)
            return error.InvalidPid;
        posix.ptrace(linux.PTRACE.ATTACH, pid, 0, 0) catch |err| {
            std.debug.print("error : {s}\n", .{@errorName(err)});
            return error.AttachFailed;
        };
        var proc: Process = .init(pid, false, true);
        _ = proc.wait_on_signal();
        return proc;
    }
    pub fn resume_process(proc: *Process) !void {
        posix.ptrace(linux.PTRACE.CONT, proc.pid, 0, 0) catch {
            // std.debug.panic("Couldn't continue\n", .{});
            return error.ResumeError;
        };
        proc.state = .Running;
    }

    pub fn wait_on_signal(proc: *Process) StopReason {
        // var wait_status: u32 = undefined;
        const options = 0;
        const res = posix.waitpid(proc.pid, options);
        const stop_reason: StopReason = .init(res.status);
        proc.state = stop_reason.reason;
        return stop_reason;
    }
};
// fn perror(msg: []const u8) void {
//     std.debug.print("{s}\n", .{@tagName(std.posix.errno(-1))});
//     std.debug.panic("{s}\n", .{msg});
// }

pub fn print_stop_reason(process: *const Process, reason: StopReason) void {
    std.debug.print("Process {d} ", .{process.pid});

    switch (reason.reason) {
        .Exited => {
            std.log.info("exited with status {d}\n", .{reason.info});
        },
        .Terminated => {
            std.log.info("terminated with signal {s}\n", .{signalName(reason.info)});
        },
        .Stopped => {
            std.log.info("Stopped with signal {s}\n", .{signalName(reason.info)});
        },
        .Running => {},
    }
}
pub fn signalName(sig: u32) []const u8 {
    inline for (@typeInfo(linux.SIG).@"struct".decls) |decl| {
        const field_value = @field(linux.SIG, decl.name);
        if (@TypeOf(field_value) != comptime_int) continue;
        if (field_value == sig) {
            return decl.name;
        }
    }
    return "UNKNOWN";
}
fn exit_and_set_error(channel: *Pipe, err: Err) void {
    var buf: [1]u8 = undefined;
    buf[0] = @intCast(@intFromError(err));
    channel.write(&buf) catch {};
    linux.exit(-1);
}
fn process_exists(pid: linux.pid_t) bool {
    // _= pid;
    const ret = linux.kill(pid, 0);
    const err = linux.E.init(ret);
    return ret != -1 and err != .SRCH;
}
fn get_process_status(pid: posix.pid_t) !u8 {
    var buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "/proc/{}/stat", .{pid}) catch unreachable;
    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch unreachable;
    defer file.close();
    const max_line_length: usize = 8192;
    const line_data = file.reader().readUntilDelimiterAlloc(std.heap.page_allocator, '\n', max_line_length) catch unreachable;
    defer std.heap.page_allocator.free(line_data);

    const index_of_last_parenthesis = std.mem.lastIndexOf(u8, line_data, &[_]u8{')'}) orelse return error.InvalidFormat;
    if (index_of_last_parenthesis + 2 >= line_data.len) {
        return error.InvalidFormat;
    }

    return line_data[index_of_last_parenthesis + 2];
}
test "process launch" {
    const process = try Process.launch("yes", true);
    defer process.deinit();
    try std.testing.expect(process_exists(process.pid));
}

test "no such program" {
    const process = Process.launch("no_such_program_aaa", true);
    try std.testing.expectError(Err.ExecError, process);
}

test "attach success" {
    const proc: Process = try .launch("zig-out/bin/run_endlessly", true);
    defer proc.deinit();
    const status = try get_process_status(proc.pid);
    try std.testing.expectEqual('t', status);
}

test "attach invalid pid" {
    const proc = Process.attach(0);
    try std.testing.expectError(error.InvalidPid, proc);
}

test "resume success" {
    {
        var proc: Process = try .launch("zig-out/bin/run_endlessly", true);
        defer proc.deinit();
        try proc.resume_process();
        const status = try get_process_status(proc.pid);
        try std.testing.expect(status == 'R' or status == 'S');
    }
    {
        var target: Process = try .launch("zig-out/bin/run_endlessly", false);
        defer target.deinit();
        var proc: Process = try .attach(target.pid);
        try proc.resume_process();
        const status = try get_process_status(proc.pid);
        try std.testing.expect(status == 'R' or status == 'S');
    }
}
test "resume already terminated"{
    var proc:Process = try .launch("zig-out/bin/end_immediately",true);
    try proc.resume_process();
    _ =proc.wait_on_signal();
    const err = proc.resume_process();
    try std.testing.expectError(error.ResumeError,err);

}