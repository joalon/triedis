const std = @import("std");

const Commands = enum {
    exit,
    ping,
    echo,
    create,
    numtries,

    pub const CommandsTable = [@typeInfo(Commands).Enum.fields.len][:0]const u8{
        "exit",
        "ping",
        "echo",
        "create",
        "numtries",
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
    } else if (std.mem.eql(u8, str, "create")) {
        return Commands.create;
    } else if (std.mem.eql(u8, str, "numtries")) {
        return Commands.numtries;
    }
    return null;
}

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    const port = 4657;
    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);

    // var server = Server{ .exit = false, .address = addr, .tries = std.StringHashMap(Trie).init(gpa) };
    // defer gpa.free(server.tries);
    var server = Server{ .exit = false, .address = addr, .tries = std.StringHashMap(u8).init(gpa) };

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
                .create => {
                    std.log.info("Got create command", .{});
                    const name = msg[command.len + 1 ..];
                    // TODO: Use a new allocator when creating a trie
                    // try server.tries.put(name, Trie.init(gpa));
                    _ = name;
                },
                .numtries => {
                    std.log.info("Got numtries command", .{});
                    const numtries = try std.fmt.allocPrint(
                        gpa,
                        "{d}\n",
                        .{server.tries.count()},
                    );
                    defer gpa.free(numtries);

                    _ = try writer.write(numtries);
                },
            }
        }
    }
}

const Server = struct {
    address: std.net.Address,
    tries: std.StringHashMap(u8),
    exit: bool,
};

const TrieNode = struct {
    const Self = @This();

    children: std.AutoHashMap(u8, TrieNode),
    endsWord: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .children = std.AutoHashMap(u8, TrieNode).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        std.debug.print("In deinit.\n", .{});
        var iter = self.children.valueIterator();
        while (iter.next()) |node| {
            node.deinit();
        }
        self.children.deinit();
    }
};

const testing = std.testing;

test "Create and destroy TrieNodes" {
    var parent = TrieNode.init(testing.allocator);
    defer parent.deinit();

    var child = TrieNode.init(testing.allocator);

    const grandChild = TrieNode.init(testing.allocator);
    try child.children.put(1, grandChild);

    try parent.children.put(1, child);

    try testing.expectEqual(1, parent.children.count());
    try testing.expectEqual(1, child.children.count());
}
