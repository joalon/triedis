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
    insert,
    prefixsearch,

    pub const CommandsTable = [@typeInfo(Commands).Enum.fields.len][:0]const u8{
        "ping",
        "insert",
        "prefixsearch",
    };

    pub fn str(self: Commands) [:0]const u8 {
        return CommandsTable[std.meta.enumToInt(self)];
    }
};

fn parseCommand(str: []const u8) ?Commands {
    if (std.mem.eql(u8, str, "ping")) {
        return Commands.ping;
    } else if (std.mem.eql(u8, str, "insert")) {
        return Commands.insert;
    } else if (std.mem.eql(u8, str, "prefixsearch")) {
        return Commands.prefixsearch;
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

    var arguments = std.mem.splitScalar(u8, std.mem.trim(u8, msg, "\n"), ' ');
    const command = arguments.next().?;
    const parsed = parseCommand(command) orelse {
        std.log.info("client sent invalid command: {s}", .{command});
        return .rearm;
    };

    switch (parsed) {
        .ping => {
            std.log.info("Got ping command", .{});
            tcp.write(loop, &conn.writeCompletion, .{ .slice = "pong" }, Connection, conn, writeCallback);
        },
        .insert => {
            const name = std.fmt.allocPrint(conn.allocator, "{s}", .{arguments.next().?}) catch |err| {
                std.log.err("An error occurred during name allocation in .insert: {any}\n", .{err});
                return .rearm;
            };

            // create new trie if not exists
            if (conn.server.tries.get(name) == null) {
                std.log.info("creating '{s}'", .{name});
                const newTrie = conn.allocator.create(Trie) catch |err| {
                    std.log.err("An error occurred during trie allocation in .insert: {any}\n", .{err});
                    return .rearm;
                };
                newTrie.* = Trie.init(conn.allocator);

                _ = conn.server.tries.put(name, newTrie) catch |err| {
                    std.log.err("An error occurred when creating the new trie in .insert: {any}", .{err});
                    return .rearm;
                };
            }

            // insert new word into trie
            const insertString = arguments.next().?;

            var trie = conn.server.tries.get(name).?;
            trie.insert(insertString) catch |err| {
                std.log.err("An error occurred during insertion in .insert: {any}", .{err});
                return .rearm;
            };
        },
        .prefixsearch => {
            const triename = arguments.next().?;
            const searchString = arguments.next().?;

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
