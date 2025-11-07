// Test runner implementation partially from https://www.openmymind.net/Using-A-Custom-Test-Runner-In-Zig/

const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const CtrfReport = struct {
    var Self = @This();

    results: struct { tool: struct { name: []const u8 } },
    summary: struct {
        tests: usize,
        passed: usize,
        failed: usize,
        skipped: usize,
        start: i64,
        stop: i64,
    },
    tests: []const Test,

    const Test = struct {
        name: []const u8,
        status: []const u8,
        duration: usize,
    };
    // environment: struct {
    //     appName: []u8,
    //     appVersion: []u8,
    // }
};

pub fn main() !void {
    var mem: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&mem);

    const allocator = fba.allocator();

    const tests_start = std.time.milliTimestamp();

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    var test_timer = try std.time.Timer.start();

    var tests_list: std.ArrayList(CtrfReport.Test) = .empty;

    for (builtin.test_functions) |t| {
        var status = Status.passed;

        const friendly_name = blk: {
            const name = t.name;
            var it = std.mem.splitScalar(u8, name, '.');
            while (it.next()) |value| {
                if (std.mem.eql(u8, value, "test")) {
                    const rest = it.rest();
                    break :blk if (rest.len > 0) rest else name;
                }
            }
            break :blk name;
        };

        std.testing.allocator_instance = .{};

        test_timer.reset();
        const result = t.func();
        const test_time = test_timer.lap();

        if (std.testing.allocator_instance.deinit() == .leak) {
            leak += 1;
        }

        if (result) |_| {
            pass += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip += 1;
                status = .skipped;
            },
            else => {
                status = .failed;
                fail += 1;
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            },
        }

        try tests_list.append(allocator, CtrfReport.Test{ .name = friendly_name, .status = std.enums.tagName(Status, status).?, .duration = test_time });
    }

    const tests_stop = std.time.milliTimestamp();

    const total_tests = pass + fail;

    const ctrfReport = CtrfReport{ .results = .{ .tool = .{ .name = "zig" } }, .summary = .{
        .tests = total_tests,
        .failed = fail,
        .passed = pass,
        .skipped = skip,
        .start = tests_start,
        .stop = tests_stop,
    }, .tests = try tests_list.toOwnedSlice(allocator) };
    const fmt = std.json.fmt(ctrfReport, .{ .whitespace = .indent_2 });

    var writer = std.Io.Writer.Allocating.init(allocator);
    try fmt.format(&writer.writer);
    const json_string = try writer.toOwnedSlice();

    std.debug.print("{s}\n", .{json_string});

    std.posix.exit(if (fail == 0) 0 else 1);
}

const Status = enum {
    passed,
    failed,
    skipped,
};
