// Test runner implementation partially from https://www.openmymind.net/Using-A-Custom-Test-Runner-In-Zig/

const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const Status = enum {
    passed,
    failed,
    skipped,
};

const Report = struct {
    var Self = @This();

    results: struct {
        tool: struct { name: []const u8, version: []const u8 },
        summary: struct {
            tests: usize,
            passed: usize,
            failed: usize,
            skipped: usize,
            start: i64,
            stop: i64,
        },
        tests: []const TestStatus,
    },

    const TestStatus = struct {
        name: []const u8,
        status: []const u8,
        duration: usize,
    };
};

pub fn main() !void {
    var mem: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&mem);

    const allocator = fba.allocator();

    const testsStart = std.time.milliTimestamp();

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    var testTimer = try std.time.Timer.start();

    var testStatusList: std.ArrayList(Report.TestStatus) = .empty;

    for (builtin.test_functions) |t| {
        var status = Status.passed;

        const friendlyName = blk: {
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

        testTimer.reset();
        const result = t.func();
        const testTime = testTimer.lap();

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

        try testStatusList.append(allocator, Report.TestStatus{ .name = friendlyName, .status = std.enums.tagName(Status, status).?, .duration = testTime });
    }

    const testsStop = std.time.milliTimestamp();

    const totalTests = pass + fail;

    const ctrfReport = Report{ .results = .{
        .tool = .{ .name = "zig", .version = builtin.zig_version_string },
        .summary = .{
            .tests = totalTests,
            .failed = fail,
            .passed = pass,
            .skipped = skip,
            .start = testsStart,
            .stop = testsStop,
        },
        .tests = try testStatusList.toOwnedSlice(allocator),
    } };
    const fmt = std.json.fmt(ctrfReport, .{ .whitespace = .indent_2 });

    var writer = std.Io.Writer.Allocating.init(allocator);
    try fmt.format(&writer.writer);
    const json_string = try writer.toOwnedSlice();

    std.debug.print("{s}\n", .{json_string});

    std.posix.exit(if (fail == 0) 0 else 1);
}
