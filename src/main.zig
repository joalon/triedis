const std = @import("std");

const Server = @import("server").Server;

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    const port = 4657;
    const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);

    std.log.info("Starting server, listening on {any}", .{address});

    var server = try Server.init(gpa, address);
    defer server.deinit();

    try server.run();

    std.log.info("Event loop done, exiting.", .{});
}
