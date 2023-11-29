const std = @import("std");
const libevdev = @import("libevdev");

pub fn listInputs(writer: anytype) !void {
    var input_dir = try std.fs.openDirAbsolute("/dev/input/by-path", .{ .iterate = true });
    defer input_dir.close();

    var iter = input_dir.iterate();
    while (try iter.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, "kbd")) continue;
        try writer.print("{s}\n", .{entry.name});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn().reader();

    var input_buffer = std.ArrayList(u8).init(allocator);
    defer input_buffer.deinit();

    const stdout_writer = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_writer);
    const stdout = bw.writer();

    var name: []const u8 = "";
    defer allocator.free(name);

    sl: while (true) {
        try stdout.writeAll("> ");
        try bw.flush();
        try stdin.streamUntilDelimiter(input_buffer.writer(), '\n', null);
        defer input_buffer.clearAndFree();
        if (std.mem.startsWith(u8, input_buffer.items, "quit")) return;

        if (std.mem.startsWith(u8, input_buffer.items, "done")) {
            const path = try std.fmt.allocPrint(allocator, "/dev/input/by-path/{s}", .{name});
            defer allocator.free(path);

            std.fs.accessAbsolute(path, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    try stdout.print("Invalid Device Path: \n    {s}\n", .{path});
                    continue :sl;
                },
                else => |e| return e,
            };

            break :sl;
        }
        if (std.mem.startsWith(u8, input_buffer.items, "list")) try listInputs(stdout);
        if (std.mem.startsWith(u8, input_buffer.items, "status")) {
            try stdout.print("Selected: {s}\n", .{name});
        }
        if (std.mem.startsWith(u8, input_buffer.items, "select")) {
            var iter = std.mem.tokenizeAny(u8, input_buffer.items, " \n\t\r");

            // Skip over "select" command
            _ = iter.next().?;

            // Copy input name to name.
            allocator.free(name);
            name = try allocator.dupe(u8, iter.next().?);
        }
        try bw.flush();
    }

    std.debug.print("Selected: {s}\n", .{name});

    const path = try std.fmt.allocPrint(allocator, "/dev/input/by-path/{s}", .{name});
    defer allocator.free(path);

    // In zig, .read_only by default
    const file = try std.fs.openFileAbsolute(path, .{
        .lock_nonblocking = true,
    });
    defer file.close();
    // Handle is the OS-specific file descriptor.
    const fd: i32 = file.handle;

    var dev = try libevdev.init(fd);

    std.time.sleep(std.time.ns_per_ms * 250);
    try dev.grab(.grab);
    defer dev.grab(.ungrab) catch unreachable;

    const device_name: [*c]const u8 = try dev.get(.name);
    std.debug.print("device name: {s}\n", .{
        device_name,
    });

    var event: libevdev.InputEvent = undefined;
    while (true) {
        const result_code = dev.nextEvent(.normal, &event) catch continue;
        if (result_code == .success and std.mem.eql(u8, event.type, "EV_KEY")) {
            if (event.ev.value == libevdev.event_values.key.press) {
                std.debug.print("Key Pressed: {s}\n", .{event.code});
                if (event.ev.code == libevdev.c.KEY_ESC) {
                    std.debug.print("Exiting\n", .{});
                    return;
                }
            }
            if (event.ev.value == libevdev.event_values.key.hold) {
                std.debug.print("Key Held: {s}\n", .{event.code});
            }
            if (event.ev.value == libevdev.event_values.key.release) {
                std.debug.print("Key Released: {s}\n", .{event.code});
            }
        }
    }
}
