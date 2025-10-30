const std = @import("std");

const testing = std.testing;

const RespError = error{EncodingError};

fn encodeSimpleStringResp(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    for (input) |c| {
        if (c == '\r' or c == '\n') {
            return RespError.EncodingError;
        }
    }

    var encoded = try allocator.alloc(u8, input.len + 3);

    encoded[0] = '+';
    @memcpy(encoded[1 .. input.len + 1], input);
    @memcpy(encoded[input.len + 1 .. input.len + 3], "\r\n");

    return encoded;
}

fn encodeBulkStringResp(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try list.writer().print("${d}\r\n{s}\r\n", .{ input.len, input });

    return list.toOwnedSlice();
}

fn encodeCommandResp(allocator: std.mem.Allocator, input: []const []const u8) ![]const u8 {
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try list.writer().print("*{d}\r\n", .{input.len});
    for (input) |string| {
        try list.writer().print("${d}\r\n{s}\r\n", .{ string.len, string });
    }

    return list.toOwnedSlice();
}

test "encode string to RESP bulk string" {
    const allocator = testing.allocator;
    const expected = "$5\r\nhello\r\n";
    const input = "hello";

    const actual = try encodeBulkStringResp(allocator, input);
    defer allocator.free(actual);

    try testing.expectEqualStrings(expected, actual);
}

test "encode simple string to RESP" {
    const allocator = testing.allocator;
    const expected = "+OK\r\n";
    const input = "OK";

    const result = try encodeSimpleStringResp(allocator, input);
    defer allocator.free(result);

    try testing.expectEqualStrings(expected, result);
}

test "simple resp string mustn't contain \\r or \\n" {
    const allocator = testing.allocator;
    const expected = RespError.EncodingError;
    const input = "Not\nOk";

    const result = encodeSimpleStringResp(allocator, input);

    try testing.expectError(expected, result);
}

test "encode an array of strings to RESP array of bulk string" {
    const allocator = testing.allocator;
    const expected = "*2\r\n$4\r\nLLEN\r\n$6\r\nmylist\r\n";
    const input = [_][]const u8{ "LLEN", "mylist" };

    const result = try encodeCommandResp(allocator, &input);
    defer allocator.free(result);

    try testing.expectEqualStrings(expected, result);
}
