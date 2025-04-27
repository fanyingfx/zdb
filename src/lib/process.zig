const std = @import("std");
const linux = std.os.linux;
const ProcessState = enum { Stopped, Running, Exited, Terminated };
const StopReason = struct {
    reason: ProcessState,
    info: u32,
    pub fn init(wait_status: u32) StopReason {
        var stop_reason: StopReason = undefined;
        if (linux.W.IFEXITED(wait_status)) {
            stop_reason.reason = .Exited;
            stop_reason.info = linux.W.EXITSTATUS(wait_status);
        } else if (linux.W.IFSIGNALED(wait_status)) {
            stop_reason.reason = .Terminated;
            stop_reason.info = linux.W.TERMSIG(wait_status);
        } else if (linux.W.IFSTOPPED(wait_status)) {
            stop_reason.reason = .Stopped;
            stop_reason.info = linux.W.STOPSIG(wait_status);
        }
        return stop_reason;
    }
};
pub const Process = struct {
    pid_: linux.pid_t = 0,
    terminate_on_end_: bool = true,
    state_: ProcessState = .Stopped,
    pub fn init(pid: linux.pid_t, terminater_on_end: bool) Process {
        return .{ .pid_ = pid, .terminate_on_end_ = terminater_on_end };
    }

    pub fn launch(path: [*:0]const u8) !Process {
        const pid: linux.pid_t = @intCast(linux.fork());
        if (pid < 0) {
            return error.ForkFailed;
        }
        if (pid == 0) {
            if (linux.ptrace(linux.PTRACE.TRACEME, 0, 0, 0, 0) < 0) {
                perror("Trace Failed!");
            }
            std.posix.execvpeZ(path, &.{null}, &.{null}) catch return error.ExecError;
        }
        var proc: Process = .init(pid, true);
        _ = proc.wait_on_signal();
        return proc;
    }
    pub fn attach(pid: linux.pid_t) !Process {
        if (pid <= 0)
            return error.InvalidPid;
        if (linux.ptrace(linux.PTRACE.ATTACH, pid, 0, 0, 0) < 0) {
            return error.AttachFailed;
        }
        var proc: Process = .init(pid, false);
        _ = proc.wait_on_signal();
        return proc;
    }
    pub fn resume_process(proc: *Process) void {
        if (linux.ptrace(linux.PTRACE.CONT, proc.pid_, 0, 0, 0) < 0) {
            std.debug.panic("Couldn't continue\n", .{});
        }
        proc.state_ = .Running;
    }

    pub fn wait_on_signal(proc: *Process) StopReason {
        var wait_status: u32 = undefined;
        const options = 0;
        if (linux.waitpid(proc.pid_, &wait_status, options) < 0) {
            perror("waitpid failed\n");
        }
        const stop_reason: StopReason = .init(wait_status);
        proc.state_ = stop_reason.reason;
        return stop_reason;
        // std.debug.print("wait_status: {d}\n", .{wait_status});
    }
};
fn perror(msg: []const u8) void {
    std.debug.print("{s}\n", .{@tagName(std.posix.errno(-1))});
    std.debug.panic("{s}\n", .{msg});
}
pub fn print_stop_reason(process: *const Process, reason: StopReason) void {
    std.debug.print("Process {d} ", .{process.pid_});

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
// pub fn signalName(sig: u32) []const u8 {
//     return switch (sig) {
//         linux.SIG.HUP
//         1 => "HUP",
//         2 => "INT",
//         3 => "QUIT",
//         4 => "ILL",
//         5 => "TRAP",
//         6 => "ABRT",
//         7 => "BUS",
//         8 => "FPE",
//         9 => "KILL",
//         11 => "SEGV",
//         13 => "PIPE",
//         14 => "ALRM",
//         15 => "TERM",
//         else => "UNKNOWN",
//     };
// }
pub fn signalName(sig: u32) []const u8 {
    const sig_type = @TypeOf(linux.SIG);
    const info = @typeInfo(sig_type);
    switch (info) {
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                const field_value = @field(linux.SIG, field.name);
                if (field_value == sig) {
                    return field.name;
                }
            }
        },
        else => {},
    }
    // inline for (fields) |field| {
    //     const field_value = @field(sig_type, field.name);
    //     if (field_value == sig) {
    //         return field.name;
    //     }
    // }

    return "UNKNOWN";
}
