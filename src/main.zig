const std = @import("std");
const libevdev = @import("lib.zig");

pub fn main() !void {
    // In zig, .read_only by default
    const file = try std.fs.openFileAbsolute(
        "/dev/input/by-id/usb-Wooting_WootingOne_WOOT_002_A01B1809W011H00466-if01-event-kbd",
        .{
            .lock_nonblocking = true,
        },
    );
    defer file.close();
    // Handle is the OS-specific file descriptor.
    const fd: i32 = file.handle;

    var dev = try libevdev.init(fd);
    // try dev.grab(.grab);
    // defer dev.grab(.ungrab) catch unreachable;

    const name: [*c]const u8 = try dev.get(.name);
    std.debug.print("device name: {s}\n", .{
        name,
    });

    var ev: libevdev.InputEvent = undefined;
    while (true) {
        const result_code = dev.nextEvent(.normal, &ev) catch continue;
        if (result_code == .success and std.mem.eql(u8, ev.type, "EV_KEY")) {
            if (ev.ev.value == 1) {
                std.debug.print("Key Pressed: {s}\n", .{ev.code});
                if (ev.ev.code == libevdev.c.KEY_ESC) {
                    std.debug.print("Exiting\n", .{});
                    return;
                }
            }
        }
    }
}