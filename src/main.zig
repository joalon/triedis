const std = @import("std");
const xev = @import("xev");

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
            const parsed = parseCommand(command);
            if (parsed == null) {
                _ = try writer.write("invalid command\n");
                continue;
            }

            std.log.info("Received command: {s}", .{command});
            if (msg.len > command.len + 1) {
                std.log.info("With arguments: {s}", .{msg[command.len + 1 ..]});
            }

            switch (parsed.?) {
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

const Trie = struct {
    const Self = @This();

    root: ?TrieNode = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.root == null) {
            return;
        }

        self.root.?.deinit();
    }

    pub fn insert(self: *Self, str: []const u8) !void {
        if (self.root == null) {
            self.root = TrieNode.init(self.allocator);
        }
        var currentNode = &self.root.?;
        for (str) |char| {
            const next = try currentNode.children.getOrPut(char);
            if (!next.found_existing) {
                next.value_ptr.* = TrieNode.init(self.allocator);
            }
            currentNode = next.value_ptr;
        }
        currentNode.endsWord = true;
    }

    pub fn contains(self: *Self, str: []const u8) bool {
        if (self.root == null) {
            return false;
        }
        var currentNode = &self.root.?;
        for (str) |char| {
            var next = currentNode.children.get(char);
            if (next == null) {
                return false;
            }
            currentNode = &next.?;
        }
        if (currentNode.endsWord) {
            return true;
        }
        return false;
    }

    pub fn prefixSearch(self: *Self, result: *std.ArrayList([]const u8), str: []const u8) !void {
        if (self.root == null) {
            return;
        }

        var currentNode = &self.root.?;
        for (str) |char| {
            var next = currentNode.children.get(char);
            if (next == null) {
                return;
            }
            currentNode = &next.?;
        }

        try self._prefixSearchRecursive(str, currentNode, result);
        return;
    }

    fn _prefixSearchRecursive(self: *Self, currentWord: []const u8, currentNode: *TrieNode, result: *std.ArrayList([]const u8)) !void {
        if (currentNode.endsWord) {
            const added = try std.fmt.allocPrint(self.allocator, "{s}", .{currentWord});
            try result.append(added);
        }

        var iter = currentNode.children.keyIterator();
        while (iter.next()) |char| {
            const newWord = try std.fmt.allocPrint(self.allocator, "{s}{c}", .{ currentWord, char.* });
            defer self.allocator.free(newWord);

            var nextNode = currentNode.children.get(char.*).?;
            try self._prefixSearchRecursive(newWord, &nextNode, result);
        }
    }
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
        var iter = self.children.valueIterator();
        while (iter.next()) |node| {
            node.deinit();
        }
        self.children.deinit();
    }
};

const testing = std.testing;

test "Prefix search" {
    var trie = Trie.init(testing.allocator);
    defer trie.deinit();

    try trie.insert("cat");
    try trie.insert("category");
    try trie.insert("cathedral");
    try trie.insert("castle");

    var result = std.ArrayList([]const u8).init(testing.allocator);
    defer result.deinit();

    try trie.prefixSearch(&result, "cat");

    try testing.expect(result.items.len == 3);

    const cat: []const u8 = "cat";
    try testing.expect(std.mem.eql(u8, cat, result.items[0]));

    const category: []const u8 = "category";
    try testing.expect(std.mem.eql(u8, category, result.items[1]));

    const cathedral: []const u8 = "cathedral";
    try testing.expect(std.mem.eql(u8, cathedral, result.items[2]));

    for (result.items) |foundStr| {
        defer testing.allocator.free(foundStr);
    }
}

test "Contains a string" {
    var trie = Trie.init(testing.allocator);
    defer trie.deinit();

    try trie.insert("abcde");
    try trie.insert("category");

    try testing.expect(trie.contains("abcde"));
    try testing.expect(trie.contains("abcd") == false);

    try testing.expect(trie.contains("category"));
    try testing.expect(trie.contains("cat") == false);
    try testing.expect(trie.contains("categorical") == false);
    try testing.expect(trie.contains("categorys") == false);
}

test "Insert into a trie" {
    var trie = Trie.init(testing.allocator);
    defer trie.deinit();

    try trie.insert("abcde");

    try testing.expectEqual(1, trie.root.?.children.count());
}

test "Create and destroy Tries" {
    var trie = Trie.init(testing.allocator);
    defer trie.deinit();

    trie.root = TrieNode.init(testing.allocator);

    const child = TrieNode.init(testing.allocator);
    try trie.root.?.children.put(1, child);

    try testing.expectEqual(1, trie.root.?.children.count());
}

test "Create and destroy TrieNodes" {
    var parent = TrieNode.init(testing.allocator);
    defer parent.deinit();

    var child1 = TrieNode.init(testing.allocator);
    const child2 = TrieNode.init(testing.allocator);

    const grandChild = TrieNode.init(testing.allocator);
    try child1.children.put(1, grandChild);

    try parent.children.put(1, child1);
    try parent.children.put(2, child2);

    try testing.expectEqual(2, parent.children.count());
    try testing.expectEqual(1, child1.children.count());
}
