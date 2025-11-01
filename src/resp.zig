const std = @import("std");

const testing = std.testing;

const RespError = error{ EncodingError, DecodingError };

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
    var list: std.ArrayList(u8) = .empty;

    try list.writer(allocator).print("${d}\r\n{s}\r\n", .{ input.len, input });

    return list.toOwnedSlice(allocator);
}

fn encodeCommandResp(allocator: std.mem.Allocator, input: []const []const u8) ![]const u8 {
    var list: std.ArrayList(u8) = .empty;

    try list.writer(allocator).print("*{d}\r\n", .{input.len});
    for (input) |string| {
        try list.writer(allocator).print("${d}\r\n{s}\r\n", .{ string.len, string });
    }

    return list.toOwnedSlice(allocator);
}

pub fn decodeCommandResp(allocator: std.mem.Allocator, input: []const u8) ![][]const u8 {
    if (input.len == 0) return error.InvalidInput;

    var result = std.ArrayList([]const u8).init(allocator);
    errdefer result.deinit();

    if (input[0] != '*') return error.InvalidRespFormat;

    var pos: usize = 1;

    const array_len = try parseInteger(input, &pos);
    if (array_len < 0) return error.InvalidArrayLength;

    if (!expectCRLF(input, &pos)) return error.MissingCRLF;

    var i: usize = 0;
    while (i < @as(usize, @intCast(array_len))) : (i += 1) {
        const str = try parseBulkString(allocator, input, &pos);
        try result.append(str);
    }

    return result.toOwnedSlice();
}
fn parseInteger(input: []const u8, pos: *usize) !i64 {
    var result: i64 = 0;
    var negative = false;

    if (pos.* >= input.len) return error.UnexpectedEnd;

    if (input[pos.*] == '-') {
        negative = true;
        pos.* += 1;
    }

    while (pos.* < input.len and input[pos.*] >= '0' and input[pos.*] <= '9') {
        result = result * 10 + @as(i64, input[pos.*] - '0');
        pos.* += 1;
    }

    return if (negative) -result else result;
}

fn expectCRLF(input: []const u8, pos: *usize) bool {
    if (pos.* + 1 >= input.len) return false;
    if (input[pos.*] != '\r' or input[pos.* + 1] != '\n') return false;
    pos.* += 2;
    return true;
}

fn parseBulkString(allocator: std.mem.Allocator, input: []const u8, pos: *usize) ![]const u8 {
    if (pos.* >= input.len or input[pos.*] != '$') return error.InvalidBulkString;
    pos.* += 1;

    const str_len = try parseInteger(input, pos);
    if (str_len < 0) return error.InvalidStringLength;

    if (!expectCRLF(input, pos)) return error.MissingCRLF;

    const len = @as(usize, @intCast(str_len));

    if (pos.* + len > input.len) return error.UnexpectedEnd;

    const str_data = try allocator.dupe(u8, input[pos.* .. pos.* + len]);
    pos.* += len;

    if (!expectCRLF(input, pos)) return error.MissingCRLF;

    return str_data;
}

test "decoding a RESP array with bulk strings" {
    const allocator = testing.allocator;
    const expected: []const []const u8 = &[_][]const u8{ "LLEN", "mylist" };
    const input = "*2\r\n$4\r\nLLEN\r\n$6\r\nmylist\r\n";

    const actual = try decodeCommandResp(allocator, input);
    defer {
        for (actual) |str| {
            allocator.free(str);
        }
        allocator.free(actual);
    }

    try std.testing.expectEqualDeep(expected, actual);
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
