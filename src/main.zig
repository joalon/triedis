const std = @import("std");

const Server = @import("server").Server;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var port: u16 = 4657;
    var host: []const u8 = "127.0.0.1";

    var argsIterator = try std.process.ArgIterator.initWithAllocator(allocator);
    defer argsIterator.deinit();

    // Skip executable
    _ = argsIterator.next();
    while (argsIterator.next()) |arg| {
        if (std.mem.eql(u8, arg, "--port")) {
            const toParse = argsIterator.next() orelse {
                std.debug.print("No value after '--port' argument. Exiting\n ", .{});
                return;
            };
            port = try std.fmt.parseInt(u16, toParse, 10);
        } else if (std.mem.eql(u8, arg, "--host")) {
            host = argsIterator.next() orelse {
                std.debug.print("No string after '--host' argument. Exiting\n", .{});
                return;
            };
        } else {
            std.debug.print("Unrecognized argument '{s}'. Exiting\n", .{arg});
            return;
        }
    }

    const address = try std.net.Address.parseIp4(host, port);

    std.log.info("Starting server, listening on {s}:{d}...", .{ host, port });

    var server = try Server.init(allocator, address);
    defer server.deinit();

    try server.run();

    std.log.info("Event loop done, exiting.", .{});
}
