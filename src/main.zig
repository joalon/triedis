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
    const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);

    const tries = try gpa.create(std.StringHashMap(*Trie));
    defer gpa.destroy(tries);
    tries.* = std.StringHashMap(*Trie).init(gpa);

    var server = Server{ .allocator = gpa, .exit = false, .address = address, .tries = tries };

    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    var tcp_server = try xev.TCP.init(address);

    try tcp_server.bind(address);
    try tcp_server.listen(128);

    std.log.info("Server listening on port {d}", .{port});

    var acceptCompletion: xev.Completion = .{};
    tcp_server.accept(&loop, &acceptCompletion, Server, &server, acceptCallback);

    try loop.run(.until_done);
    std.log.info("Event loop done, exiting.", .{});
}

fn acceptCallback(
    userdata: ?*Server,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.AcceptError!xev.TCP,
) xev.CallbackAction {
    _ = completion;

    const client = result catch |err| {
        std.log.err("Accept client error: {any}.", .{err});
        return .rearm;
    };
    std.log.info("Accepted new client", .{});

    const conn = userdata.?.allocator.create(Connection) catch {
        std.debug.print("error, out of memory", .{});
        return .disarm;
    };

    client.read(loop, &conn.readCompletion, .{ .slice = &conn.buffer }, Connection, conn, readCallback);

    return .rearm;
}

const Connection = struct {
    buffer: [8192]u8,
    readCompletion: xev.Completion,
    closeCompletion: xev.Completion,
    writeCompletion: xev.Completion,

    fn init() Connection {
        return Connection{
            .buffer = undefined,
            .readCompletion = .{},
            .closeCompletion = .{},
            .writeCompletion = .{},
        };
    }
};

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
        std.debug.print("No userdata!\n", .{});
        return .disarm;
    };

    const bytesRead = result catch |err| {
        std.debug.print("No bytes read: {any}\n", .{err});
        if (err == error.EOF) {
            std.debug.print("Got EOF, closing socket.\n", .{});
            tcp.close(loop, &conn.closeCompletion, Connection, conn, closeCallback);
        }
        return .disarm;
    };

    std.debug.print("received {} bytes: {s}\n", .{ bytesRead, userdata.?.buffer[0..bytesRead] });
    tcp.write(loop, &conn.writeCompletion, .{ .slice = "message received.\n" }, Connection, conn, writeCallback);
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
        std.debug.print("an error occurred when writing the response: {any}\n", .{err});
        return .disarm;
    };

    std.debug.print("response sent.\n", .{});
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
        std.debug.print("error during connection close: {any}", .{err});
    };

    std.debug.print("connection closed.\n", .{});

    return .disarm;
}

const Server = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,
    tries: *std.StringHashMap(*Trie),
    exit: bool,
};
