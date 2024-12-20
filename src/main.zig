const std = @import("std");
const libevdev = @import("libevdev");

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

    var inputs = try libevdev.ioctl.listInputEvents(allocator);
    defer inputs.deinit();

    var name: []const u8 = "";
    defer allocator.free(name);

    for (inputs.items) |evFile| {
        const slice = std.mem.sliceTo(&evFile.file_name, 0);
        try stdout.print("/dev/input/{s: <8} -> {s}\n", .{ slice, evFile.real_name });
    }
    try stdout.print("'> ?' prints this list.\n", .{});
    try stdout.print("'> q' quit\n", .{});
    sl: while (true) {
        try stdout.writeAll("> ");
        try bw.flush();
        try stdin.streamUntilDelimiter(input_buffer.writer(), '\n', null);
        defer input_buffer.clearAndFree();
        const stripped = std.mem.trim(u8, input_buffer.items, &std.ascii.whitespace);
        if (std.mem.startsWith(u8, input_buffer.items, "q")) return;
        if (std.mem.startsWith(u8, input_buffer.items, "?")) {
            for (inputs.items) |evFile| {
                const slice = std.mem.sliceTo(&evFile.file_name, 0);
                try stdout.print("/dev/input/{s: <8} -> {s}\n", .{ slice, evFile.real_name });
            }
            try stdout.print("'> ?' prints this list.\n", .{});
            try stdout.print("'> q' quit\n", .{});
        }
        try bw.flush();

        _ = std.fmt.parseInt(u32, stripped, 10) catch continue :sl;
        for (inputs.items) |input_event| {
            const found = std.mem.indexOf(u8, &input_event.file_name, stripped) != null;
            if (found) {
                const slice = std.mem.sliceTo(&input_event.file_name, 0);
                name = try allocator.dupe(u8, slice);
                break :sl;
            }
        }
    }

    std.debug.print("Selected: {s}\n", .{name});

    const path = try std.fmt.allocPrint(allocator, "/dev/input/{s}", .{name});
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

    const device_name: []const u8 = try dev.get(.name);
    std.debug.print("device name: {s}\n", .{
        device_name,
    });

    var event: libevdev.InputEvent = undefined;
    while (true) {
        const result_code = dev.nextEvent(.normal, &event) catch continue;
        // std.debug.print("Event: {s} {s}\n", .{event.string(.type), event.string(.code)});
        if (result_code == .success and event.type == .key) {
            if (event.value.key == .press) {
                std.debug.print("Key Pressed: {s}\n", .{event.string(.code)});
                if (event.code.key == .KEY_ESC) {
                    std.debug.print("Exiting\n", .{});
                    return;
                }
                if (event.code.key == .KEY_0) {
                    std.debug.print("Wowzers! It werks!\n", .{});
                }
            }
            if (event.value.key == .hold) {
                std.debug.print("Key Held: {s}\n", .{event.string(.code)});
            }
            if (event.value.key == .release) {
                std.debug.print("Key Released: {s}\n", .{event.string(.code)});
            }
        }
    }
}
