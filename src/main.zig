const std = @import("std");

const Commands = enum {
    exit,
    ping,
    echo,

    pub const CommandsTable = [@typeInfo(Commands).Enum.fields.len][:0]const u8{
        "exit",
        "ping",
        "echo",
    };

    pub fn str(self: Commands) [:0]const u8 {
        return CommandsTable[std.meta.enumToInt(self)];
    }
};

fn parseCommand(str: []const u8) ?Commands {
    if (std.mem.eql(u8, str, "exit")) {
        return Commands.exit;
    } else if (std.mem.eql(u8, str, "ping")) {
        return Commands.ping;
    } else if (std.mem.eql(u8, str, "echo")) {
        return Commands.echo;
    }
    return null;
}

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    const port = 4657;
    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);

    var server = Server{ .exit = false, .address = addr, .tries = std.StringHashMap(Trie).init(gpa) };
    var socket = try server.address.listen(.{});

    std.log.info("Server listening on port {d}", .{port});

    while (!server.exit) {
        const client = try socket.accept();
        defer client.stream.close();

        const reader = client.stream.reader();
        const writer = client.stream.writer();
        while (true) {
            const msg = try reader.readUntilDelimiterOrEofAlloc(gpa, '\n', 65536) orelse break;
            defer gpa.free(msg);

            var arguments = std.mem.split(u8, msg, " ");
            const command = arguments.next().?;
            const parsed = parseCommand(command).?;

            std.log.info("Received command: {s}", .{command});
            if (msg.len > command.len + 1) {
                std.log.info("With arguments: {s}", .{msg[command.len + 1 ..]});
            }

            switch (parsed) {
                .exit => {
                    std.log.info("Got exit command", .{});
                    server.exit = true;
                    break;
                },
                .ping => {
                    std.log.info("Got ping command", .{});
                    _ = try writer.write("pong\n");
                },
                .echo => {
                    std.log.info("Got echo command", .{});
                    const echo = try std.fmt.allocPrint(
                        gpa,
                        "{s}\n",
                        .{msg[command.len + 1 ..]},
                    );
                    defer gpa.free(echo);

                    _ = try writer.write(echo);
                },
            }
        }
    }
}

const Server = struct {
    address: std.net.Address,
    tries: std.StringHashMap(Trie),
    exit: bool,
};

const Trie = struct {
    terminatesWord: bool,
};
