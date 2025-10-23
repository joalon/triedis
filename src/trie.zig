const std = @import("std");
const testing = std.testing;

pub const Trie = struct {
    const Self = @This();

    root: ?TrieNode = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.root) |*root| {
            root.deinit();
        }
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
