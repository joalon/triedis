const std = @import("std");

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    const port = 4657;
    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
    var socket = try addr.listen(.{});

    std.log.info("Server listening on port {d}", .{port});

    while (true) {
        const client = try socket.accept();
        const reader = client.stream.reader();
        while (true) {
            const msg = try reader.readUntilDelimiterOrEofAlloc(gpa, '\n', 65536) orelse break;
            defer gpa.free(msg);

            if (std.mem.eql(u8, msg, "quit")) {
                std.log.info("client exited", .{});
                break;
            }

            std.log.info("Message: {s}", .{msg});
        }
    }
}
