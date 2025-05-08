const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;  

pub const Pipe = struct {
    const read_fd = 0;
    const write_fd = 1;
    fds: [2]posix.fd_t,

    pub fn init(close_on_exec: bool) !Pipe {
        var pipe:Pipe = undefined;
        pipe.fds = try posix.pipe2(.{ .CLOEXEC =close_on_exec} );
        return pipe;
    }
    pub fn deinit(self: *Pipe) void {
        self.close_read();
        self.close_write();
    }

    fn release_read(self: *Pipe) i32 {
        const val = self.fds[read_fd];
        self.fds[read_fd] = -1;
        return val;
    }
    fn realse_write(self: *Pipe) i32 {
        const val = self.fds[write_fd];
        self.fds[write_fd] = -1;
        return val;
    }
    pub fn close_read(self: *Pipe) void {
        if (self.fds[read_fd] != -1) {
            std.posix.close(self.fds[read_fd]);
            self.fds[read_fd] = -1;
        }
    }
    pub fn close_write(self: *Pipe) void {
        if (self.fds[write_fd] != -1) {
            posix.close(self.fds[write_fd]);
            self.fds[write_fd] = -1;
        }
    }
    pub fn read(self: *Pipe, buf:[]u8) ![]u8 {
        // var buf: [1024]u8 = undefined;
        const chars_read = try std.posix.read(self.fds[read_fd], buf,);
        return buf[0..chars_read];
    }
    pub fn write(self: *Pipe, from: []u8) !void {
        _=try std.posix.write(self.fds[write_fd], from);
    }
};
