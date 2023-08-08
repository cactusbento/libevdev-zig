const std = @import("std");
const libevdev = @import("lib.zig");

pub fn main() !void {
    std.debug.print("Hello World!\n", .{});

    // In zig, .read_only by default
    const file = try std.fs.openFileAbsolute(
        "/dev/input/by-id/usb-KBDFANS_TIGER80-event-kbd",
        .{
            .lock_nonblocking = true,
        },
    );
    defer file.close();
    // Handle is the OS-specific file descriptor.
    const fd: i32 = file.handle;

    var dev = try libevdev.init(fd);
    const name: [*c]const u8 = try dev.get(.name);

    var ev: libevdev.InputEvent = undefined;

    std.debug.print("device name: {s}\n", .{
        name,
    });

    while (true) {
        const result_code = dev.nextEvent(.normal, &ev) catch continue;
        if (result_code == .success and std.mem.eql(u8, ev.type, "EV_KEY")) {
            if (ev.ev.value == 0) {
                if (std.mem.eql(u8, ev.code, "KEY_SPACE")) {
                    try dev.grab(.ungrab);
                }
            }
            if (ev.ev.value == 1) {
                if (std.mem.eql(u8, ev.code, "KEY_SPACE")) {
                    try dev.grab(.grab);
                }
            }
        }
    }
}
