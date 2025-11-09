const std = @import("std");
const xev = @import("xev");
const resp = @import("resp");

const testing = std.testing;

const Trie = @import("trie").Trie;

pub const Server = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,
    tries: *std.StringHashMap(*Trie),

    pub fn init(allocator: std.mem.Allocator, address: std.net.Address) !Server {
        const tries = try allocator.create(std.StringHashMap(*Trie));
        tries.* = std.StringHashMap(*Trie).init(allocator);
        return Server{ .allocator = allocator, .address = address, .tries = tries };
    }

    pub fn deinit(self: Server) void {
        self.allocator.destroy(self.tries);
    }

    pub fn run(self: *Server) !void {
        var loop = try xev.Loop.init(.{});
        defer loop.deinit();

        var tcp_server = try xev.TCP.init(self.address);

        try tcp_server.bind(self.address);
        try tcp_server.listen(128);

        var acceptCompletion: xev.Completion = .{};
        tcp_server.accept(&loop, &acceptCompletion, Server, self, acceptCallback);

        try loop.run(.until_done);
    }
};

const Request = struct {
    command: Commands,
    arguments: [][]const u8,
};

const Connection = struct {
    allocator: std.mem.Allocator,
    server: *Server,
    buffer: [8192]u8,
    readCompletion: xev.Completion,
    closeCompletion: xev.Completion,
    writeCompletion: xev.Completion,

    fn init(allocator: std.mem.Allocator, server: *Server) Connection {
        return Connection{
            .allocator = allocator,
            .server = server,
            .buffer = undefined,
            .readCompletion = .{},
            .closeCompletion = .{},
            .writeCompletion = .{},
        };
    }
};

const Commands = enum {
    ping,
    set,
    get,
    tprefix,

    pub const CommandsTable = [@typeInfo(Commands).Enum.fields.len][:0]const u8{
        "ping",
        "set",
        "get",
        "tprefix",
    };

    pub fn str(self: Commands) [:0]const u8 {
        return CommandsTable[std.meta.enumToInt(self)];
    }
};

fn parseCommand(allocator: std.mem.Allocator, str: []const u8) ?Commands {
    const lowercase = std.ascii.allocLowerString(allocator, str) catch {
        return null;
    };
    defer allocator.free(lowercase);

    if (std.mem.eql(u8, lowercase, "ping")) {
        return Commands.ping;
    } else if (std.mem.eql(u8, lowercase, "set")) {
        return Commands.set;
    } else if (std.mem.eql(u8, lowercase, "get")) {
        return Commands.get;
    } else if (std.mem.eql(u8, lowercase, "tprefix")) {
        return Commands.tprefix;
    }
    return null;
}

fn acceptCallback(
    userdata: ?*Server,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.AcceptError!xev.TCP,
) xev.CallbackAction {
    _ = completion;

    const server = userdata orelse {
        std.log.err("No userdata in acceptCallback!", .{});
        return .rearm;
    };

    const client = result catch |err| {
        std.log.err("Accept client error: {any}.", .{err});
        return .rearm;
    };
    std.log.info("Accepted new client", .{});

    const conn = server.allocator.create(Connection) catch {
        std.log.err("error, out of memory", .{});
        return .disarm;
    };
    conn.* = Connection.init(server.allocator, server);

    client.read(loop, &conn.readCompletion, .{ .slice = &conn.buffer }, Connection, conn, readCallback);

    return .rearm;
}

fn readCallback(
    userdata: ?*Connection,
    loop: *xev.Loop,
    completion: *xev.Completion,
    tcp: xev.TCP,
    buffer: xev.ReadBuffer,
    result: xev.ReadError!usize,
) xev.CallbackAction {
    _ = completion;
    _ = buffer;

    const conn = userdata orelse {
        std.log.err("No userdata!\n", .{});
        return .disarm;
    };

    const bytesRead = result catch |err| {
        if (err == error.EOF) {
            tcp.close(loop, &conn.closeCompletion, Connection, conn, closeCallback);
        }
        return .disarm;
    };

    const msg = conn.buffer[0..bytesRead];
    var request: Request = undefined;

    if (msg[0] == '*') {
        std.log.info("Got RESP command", .{});
        var arguments = resp.decodeCommandResp(conn.allocator, msg) catch |err| {
            std.log.err("An error occurred during RESP decoding: {any}\n", .{err});
            return .rearm;
        };
        defer {
            for (arguments) |str| {
                conn.allocator.free(str);
            }
            conn.allocator.free(arguments);
        }
        const parsed = parseCommand(conn.allocator, arguments[0]) orelse {
            std.log.info("client sent invalid command: {s}", .{arguments[0]});
            return .rearm;
        };
        request.command = parsed;
        request.arguments = arguments[1..arguments.len];
    } else {
        var argumentsIter = std.mem.splitScalar(u8, std.mem.trim(u8, msg, "\n"), ' ');
        var list: std.ArrayList([]const u8) = .empty;
        while (argumentsIter.next()) |arg| {
            list.append(conn.allocator, arg) catch |err| {
                std.log.err("An error occurred during argument allocation: {any}\n", .{err});
                return .rearm;
            };
        }
        const arguments = list.toOwnedSlice(conn.allocator) catch |err| {
            std.log.err("An error occurred during argument allocation: {any}\n", .{err});
            return .rearm;
        };

        const command = arguments[0];
        const parsed = parseCommand(conn.allocator, command) orelse {
            std.log.info("client sent invalid command: {s}", .{command});
            return .rearm;
        };
        request.command = parsed;
        request.arguments = arguments[1..arguments.len];
    }

    switch (request.command) {
        .ping => {
            std.log.info("Got ping command", .{});
            if (request.arguments.len == 1) {
                tcp.write(loop, &conn.writeCompletion, .{ .slice = request.arguments[0] }, Connection, conn, writeCallback);
                return .rearm;
            }
            tcp.write(loop, &conn.writeCompletion, .{ .slice = "pong" }, Connection, conn, writeCallback);
        },
        .set => {
            std.log.debug("Got command: '{any}', with args: {any}", .{ request.command, request.arguments });
            const trieName = std.fmt.allocPrint(conn.allocator, "{s}", .{request.arguments[0]}) catch |err| {
                std.log.err("An error occurred during name allocation in set: {any}\n", .{err});
                return .rearm;
            };

            // create new trie if not exists
            if (conn.server.tries.get(trieName) == null) {
                std.log.info("creating '{s}'", .{trieName});
                const newTrie = conn.allocator.create(Trie) catch |err| {
                    std.log.err("An error occurred during trie allocation in set: {any}\n", .{err});
                    return .rearm;
                };
                newTrie.* = Trie.init(conn.allocator);

                _ = conn.server.tries.put(trieName, newTrie) catch |err| {
                    std.log.err("An error occurred when creating the new trie in set: {any}", .{err});
                    return .rearm;
                };
            }

            // insert new word into trie
            var insertString = request.arguments[1];
            if (request.arguments[1][0] == '"') {
                insertString = std.mem.trim(u8, insertString, "\"");
            }

            var trie = conn.server.tries.get(trieName).?;
            trie.insert(insertString) catch |err| {
                std.log.err("An error occurred during insertion in .insert: {any}", .{err});
                return .rearm;
            };
        },
        .get => {
            const name = std.fmt.allocPrint(conn.allocator, "{s}", .{request.arguments[0]}) catch |err| {
                std.log.err("An error occurred during name allocation in set: {any}\n", .{err});
                return .rearm;
            };

            if (conn.server.tries.get(name)) |trie| {
                var searchString = request.arguments[1];
                if (searchString[0] == '"') {
                    searchString = std.mem.trim(u8, searchString, "\"");
                }

                if (trie.contains(searchString)) {
                    tcp.write(loop, &conn.writeCompletion, .{ .slice = "t\n" }, Connection, conn, writeCallback);
                    return .rearm;
                }
                tcp.write(loop, &conn.writeCompletion, .{ .slice = "f\n" }, Connection, conn, writeCallback);
            }
        },
        .tprefix => {
            const triename = request.arguments[0];
            var searchString = request.arguments[1];
            if (searchString[0] == '"') {
                searchString = std.mem.trim(u8, searchString, "\"");
            }

            std.log.info("searching '{s}' for '{s}'", .{ triename, searchString });

            var trie = conn.server.tries.get(triename) orelse {
                std.log.info("trie {s} doesn't exist.\n", .{triename});
                return .rearm;
            };

            var searchresult: std.ArrayList([]const u8) = .empty;
            defer conn.server.allocator.free(searchresult.items);

            trie.prefixSearch(&searchresult, searchString) catch |err| {
                std.log.err("An error occurred during prefixsearch: {any}\n", .{err});
                return .rearm;
            };

            // TODO: Batch using RESP3
            for (searchresult.items) |foundStr| {
                std.log.info("writing result: {s}", .{foundStr});
                tcp.write(loop, &conn.writeCompletion, .{ .slice = foundStr }, Connection, conn, writeCallback);
                tcp.write(loop, &conn.writeCompletion, .{ .slice = "\n" }, Connection, conn, writeCallback);
            }
        },
    }

    return .rearm;
}

fn writeCallback(
    userdata: ?*Connection,
    loop: *xev.Loop,
    completion: *xev.Completion,
    tcp: xev.TCP,
    buffer: xev.WriteBuffer,
    result: xev.WriteError!usize,
) xev.CallbackAction {
    _ = userdata;
    _ = loop;
    _ = completion;
    _ = tcp;
    _ = buffer;

    _ = result catch |err| {
        std.log.err("an error occurred when writing the response: {any}\n", .{err});
        return .disarm;
    };

    return .disarm;
}

fn closeCallback(
    userdata: ?*Connection,
    loop: *xev.Loop,
    completion: *xev.Completion,
    tcp: xev.TCP,
    result: xev.CloseError!void,
) xev.CallbackAction {
    _ = loop;
    _ = completion;
    _ = tcp;
    _ = userdata;

    result catch |err| {
        std.log.err("error during connection close: {any}", .{err});
    };

    return .disarm;
}

test "parseCommand returns ping correctly" {
    const allocator = std.testing.allocator;
    const input = "PING";
    const expected = Commands.ping;

    const actual = parseCommand(allocator, input);

    try std.testing.expect(actual == expected);
}
