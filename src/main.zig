const std = @import("std");
const xev = @import("xev");

const Trie = @import("trie").Trie;

const Commands = enum {
    exit,
    ping,
    echo,
    create,
    insert,
    numtries,
    prefixsearch,

    pub const CommandsTable = [@typeInfo(Commands).Enum.fields.len][:0]const u8{
        "exit",
        "ping",
        "echo",
        "create",
        "insert",
        "numtries",
        "prefixsearch",
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
    } else if (std.mem.eql(u8, str, "insert")) {
        return Commands.insert;
    } else if (std.mem.eql(u8, str, "numtries")) {
        return Commands.numtries;
    } else if (std.mem.eql(u8, str, "prefixsearch")) {
        return Commands.prefixsearch;
    }
    return null;
}

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    const port = 4657;
    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);

    const tries = try gpa.create(std.StringHashMap(*Trie));
    defer gpa.destroy(tries);
    tries.* = std.StringHashMap(*Trie).init(gpa);

    var server = Server{ .exit = false, .address = addr, .tries = tries };

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

            var arguments = std.mem.splitScalar(u8, msg, ' ');
            const command = arguments.next().?;
            const parsed = parseCommand(command) orelse {
                _ = try writer.write("invalid command\n");
                continue;
            };

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
                    const name = try std.fmt.allocPrint(gpa, "{s}", .{msg[command.len + 1 ..]});

                    const newTrie = try gpa.create(Trie);
                    newTrie.* = Trie.init(gpa);

                    try server.tries.put(name, newTrie);
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
                .insert => {
                    std.log.info("Got insert command", .{});
                    const trieName = arguments.next().?;
                    const insertString = arguments.next().?;

                    var trie = server.tries.get(trieName).?;
                    try trie.insert(insertString);
                },
                .prefixsearch => {
                    std.log.info("Got prefixsearch command", .{});
                    const triename = arguments.next().?;
                    const searchString = arguments.next().?;

                    var trie = server.tries.get(triename).?;

                    var result = std.ArrayList([]const u8).init(gpa);
                    defer result.deinit();

                    try trie.prefixSearch(&result, searchString);

                    for (result.items) |foundStr| {
                        _ = try writer.print("{s}\n", .{foundStr});
                        defer gpa.free(foundStr);
                    }
                },
            }
        }
    }
}

const Server = struct {
    address: std.net.Address,
    tries: *std.StringHashMap(*Trie),
    exit: bool,
};
