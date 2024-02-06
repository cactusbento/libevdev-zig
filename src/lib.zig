const std = @import("std");
pub const c = @import("translate-c/libevdev-uinput.zig");

pub const events = @import("events.zig");
pub const EventType = events.EventType;
pub const EventCode = events.EventCode;

const LibEvdev = @This();

/// Libevdev device.
evdev: *c.struct_libevdev,

/// Initialize a new libevdev device.
///
/// This function only allocates the required memory and initializes
/// the struct to sane default values. To actually hook up the device
/// to a kernel device, use `LibEvdev.setFD()`.
///
/// Memory allocated through `LibEvdev.init()` must be released by the
/// caller with `LibEvdev.deinit()`.
///
/// [libevdev-zig]: Note: providing `file_descriptor` will run
/// `LibEvdev.setFD(file_descriptor)`
pub fn init(file_descriptor: ?i32) !LibEvdev {
    var retVal: LibEvdev = .{
        .evdev = c.libevdev_new() orelse return error.FailedToInitLibevdev,
    };

    if (file_descriptor) |fd| {
        try retVal.setFD(fd);
    }

    return retVal;
}

/// Clean up and free the libevdev struct.
///
/// After completion, the `LibEvdev.evdev` is invalid and
/// must not be used.
///
/// Note that calling `LibEvdev.deinit()` does not close the
/// file descriptor currently associated with this instance.
pub fn deinit(self: *LibEvdev) void {
    c.libevdev_free(self.evdev);
}

/// Change the fd for this device, without re-reading the actual device.
///
/// If the fd changes after initializing the device, for example after a
/// VT-switch in the X.org X server, this function updates the internal
/// fd to the newly opened. No check is made that new fd points to the
/// same device. If the device has changed, libevdev's behavior is
/// undefined.
///
/// libevdev does not sync itself after changing the fd and keeps the
/// current device state. Use `LibEvdev.nextEvent()` with the
/// LIBEVDEV_READ_FLAG_FORCE_SYNC flag to force a re-sync.
///
/// The example code below illustrates how to force a re-sync of the
/// library-internal state.
/// Note that this code doesn't handle the events in the caller,
/// it merely forces an update of the internal library state.
///
/// ```zig
/// var dev: LibEvdev = LibEvdev.init(null);
/// var ev: LibEvdev.InputEvent = undefined; // Defined elsewhere
/// dev.changeFD(new_fd);
/// dev.nextEvent(LIBEVDEV_READ_FLAG_FORCE_SYNC, &ev);
/// while (dev.nextEvent(LIBEVDEV_READ_FLAG_SYNC, &ev)
///        == c.LIBEVDEV_READ_STATUS_SYNC)
///                         ; // noop
/// ```
///
/// The fd may be open in `O_RDONLY` or `O_RDWR`.
///
/// After changing the fd, the device is assumed ungrabbed and
/// a caller must call `LibEvdev.grab()` again.
pub fn changeFD(self: *LibEvdev, file_descriptor: i32) !void {
    if (c.libevdev_change_fd(self.evdev, file_descriptor) != 0)
        return error.FailedToChangeFileDescriptor;
}

/// Set the fd for this struct and initialize internal data.
///
/// The fd must be in `O_RDONLY` or `O_RDWR` mode.
///
/// This function may only be called once per device. If the device
/// changed and you need to re-read a device, use `LibEvdev.deinit()`
/// and `LibEvdev.init()`. If you need to change the fd after closing
/// and re-opening the same device, use `LibEvdev.changeFD()`.
///
/// A caller should ensure that any events currently pending on the
/// fd are drained before the file descriptor is passed to libevdev
/// for initialization. Due to how the kernel's ioctl handling works,
/// the initial device state will reflect the current device state
/// after applying all events currently pending on the fd. Thus, if
/// the fd is not drained, the state visible to the caller will be
/// inconsistent with the events immediately available on the device.
/// This does not affect state-less events like `EV_REL`.
///
/// Unless otherwise specified, libevdev function behavior is undefined
/// until a successful call to `LibEvdev.setFD()`.
pub fn setFD(self: *LibEvdev, file_descriptor: i32) !void {
    if (c.libevdev_set_fd(self.evdev, file_descriptor) != 0)
        return error.FailedToSetFd;
}

pub fn getFD(self: *LibEvdev) !i32 {
    const fd = c.libevdev_get_fd(self.evdev);
    return if (fd >= 0) fd else error.FileDescriptorNotSet;
}

pub const GrabMode = enum(u32) {
    /// Grab the device if not currently grabbed.
    grab = c.LIBEVDEV_GRAB,

    /// Ungrab the device if currently grabbed.
    ungrab = c.LIBEVDEV_UNGRAB,
};

/// Grab or ungrab the device through a kernel EVIOCGRAB.
///
/// This prevents other clients (including kernel-internal ones
/// such as rfkill) from receiving events from this device.
///
/// This is generally a bad idea. Don't do this.
///
/// Grabbing an already grabbed device, or ungrabbing an ungrabbed
/// device is a noop and always succeeds.
///
/// A grab is an operation tied to a file descriptor, not a device.
/// If a client changes the file descriptor with `LibEvdev.changeFD()`,
/// it must also re-issue a grab with `LibEvdev.grab()`.
pub fn grab(self: *LibEvdev, grab_mode: GrabMode) !void {
    if (c.libevdev_grab(self.evdev, @intFromEnum(grab_mode)) != 0)
        return error.FailedToSetGrabMode;
}

// =============================================================
//                          QUERIES
// =============================================================

pub const DeviceInfo = enum {
    not_implemented,

    /// The device's name, either as set by the caller or as read
    /// from the kernel.
    ///
    /// The string returned is valid until `LibEvdev.deinit()`
    /// or until `LibEvdev.set(.name, .{})`, whichever comes earlier.
    ///
    /// Note: Never null
    name,

    /// Retrieve the device's physical location, either as set by
    /// the caller or as read from the kernel.
    ///
    /// The string returned is valid until `LibEvdev.deinit()` or until
    /// `LibEvdev.set(.phys, .{})`, whichever comes earlier.
    ///
    /// Virtual devices such as uinput devices have no phys location.
    ///
    /// Note: Can be null
    phys,

    /// Retrieve the device's unique identifier, either as set by
    /// the caller or as read from the kernel.
    ///
    /// The string returned is valid until `LibEvdev.deinit()` or until
    /// `LibEvdev.set(.phys, .{})`, whichever comes earlier.
    ///
    /// Virtual devices such as uinput devices have no phys location.
    ///
    /// Note: Can be null
    uniq,

    id_product,
    id_vendor,
    id_bustype,
    id_version,
    driver_version,
};

pub fn get(self: *LibEvdev, comptime option: DeviceInfo) !switch (option) {
    .name,
    .phys,
    .uniq,
    => []const u8,
    .id_product,
    .id_vendor,
    .id_bustype,
    .id_version,
    .driver_version,
    => i32,
    else => void,
} {
    return switch (option) {
        .name => std.mem.sliceTo(c.libevdev_get_name(self.evdev), 0),
        .phys => std.mem.sliceTo(c.libevdev_get_phys(self.evdev), 0),
        .uniq => std.mem.sliceTo(c.libevdev_get_uniq(self.evdev), 0),
        .id_product => c.libevdev_get_id_product(self.evdev),
        .id_vendor => c.libevdev_get_id_vendor(self.evdev),
        .id_bustype => c.libevdev_get_id_bustype(self.evdev),
        .id_version => c.libevdev_get_id_version(self.evdev),
        .driver_version => c.libevdev_get_driver_version(self.evdev),
        else => error.NotImplemented,
    };
}

pub const Property = enum(i32) {
    max = c.INPUT_PROP_MAX,
    cnt = c.INPUT_PROP_CNT,
    direct = c.INPUT_PROP_DIRECT,
    pointer = c.INPUT_PROP_POINTER,
    semi_mt = c.INPUT_PROP_SEMI_MT,
    buttonpad = c.INPUT_PROP_BUTTONPAD,
    topbuttonpad = c.INPUT_PROP_TOPBUTTONPAD,
    accelerometer = c.INPUT_PROP_ACCELEROMETER,
    pointing_stick = c.INPUT_PROP_POINTING_STICK,
};

pub const HasOption = union(enum) {
    property: Property,
    event_type: EventType,
    pending_event,
};

pub fn has(self: *LibEvdev, comptime option: HasOption) bool {
    return switch (option) {
        .property => |p| c.libevdev_has_property(self.evdev, @intFromEnum(p)) != 0,
        .event_type => |et| c.libevdev_has_event_type(self.evdev, @intFromEnum(et)) != 0,
        .pending_event => c.libevdev_has_event_pending(self.evdev) != 0,
    };
}

// =============================================================
//                       EVENT HANDLING
// =============================================================

pub const ReadFlags = enum(u32) {
    sync = c.LIBEVDEV_READ_FLAG_SYNC,
    force_sync = c.LIBEVDEV_READ_FLAG_FORCE_SYNC,

    normal = c.LIBEVDEV_READ_FLAG_NORMAL,
    blocking = c.LIBEVDEV_READ_FLAG_BLOCKING,
};

pub const ReadStatus = enum {
    success,
    sync,
};

pub const InputEvent = struct {
    ev: c.struct_input_event,

    type: EventType,
    code: EventCode,
    value: i32,

    pub fn string(self: *InputEvent, field: enum { type, code }) []const u8 {
        return switch (field) {
            .type => std.mem.sliceTo(c.libevdev_event_type_get_name(self.ev.type), 0),
            .code => std.mem.sliceTo(c.libevdev_event_code_get_name(self.ev.type, self.ev.code), 0),
        };
    }
};

pub const event_values = struct {
    pub const key = struct {
        pub const release = 0;
        pub const press = 1;
        pub const hold = 2;
    };
};

/// Get the next event from the device.
///
/// This function operates in two different modes:
/// normal mode or sync mode.
///
/// In normal mode (when flags has `ReadFlags.normal` set),
/// this function returns `ReadStatus.success and` returns
/// the event in the argument `ev`. If no events are available at
/// this time, it returns `-EAGAIN` and `ev` is undefined.
///
/// If the current event is an `EV_SYN` `SYN_DROPPED` event,
/// this function returns `ReadStatus.sync` and `ev` is set
/// to the `EV_SYN` event. The caller should now call this function
/// with the `ReadFlags.sync` flag set, to get the set of
/// events that make up the device state delta. This function
/// returns `ReadStatus.sync` for each event part of that
/// delta, until it returns -EAGAIN once all events have been synced.
/// For more details on what libevdev does to sync after a `SYN_DROPPED`
/// event, see `SYN_DROPPED` handling.
///
/// If a device needs to be synced by the caller but the caller does
/// not call with the `ReadFlags.sync` flag set, all events
/// from the diff are dropped after libevdev updates its internal
/// state and event processing continues as normal. Note that the
/// current slot and the state of touch points may have updated during
/// the `SYN_DROPPED` event, it is strongly recommended that a caller
/// ignoring all sync events calls `c.libevdev_get_current_slot()` and
/// checks the `c.ABS_MT_TRACKING_ID` values for all slots.
///
/// If a device has changed state without events being enqueued in
/// libevdev, e.g. after changing the file descriptor, use the
/// `ReadFlags.force_sync` flag. This triggers an internal
/// sync of the device and `LibEvdev.nextEvent()` returns
/// `ReadStatus.sync`. Any state changes are
/// available as events as described above. If `ReadFlags.force_sync`
/// is set, the value of `ev` is undefined.
pub fn nextEvent(self: *LibEvdev, flag: ReadFlags, ev: *InputEvent) !ReadStatus {
    const result = c.libevdev_next_event(self.evdev, @intFromEnum(flag), &ev.*.ev);
    if (result < 0) return error.FailedToGetNextEvent;

    const et: EventType = @enumFromInt(ev.ev.type);
    const ec: EventCode = switch (et) {
        inline .pwr, .max, .cnt, .version, .ff_status => |tag| @unionInit(EventCode, @tagName(tag), ev.ev.value),
        inline else => |tag| fuk: {
            const ti: std.builtin.Type.Union = @typeInfo(EventCode).Union;
            comptime var tag_type: type = undefined;
            inline for (ti.fields) |uf| {
                if (comptime std.mem.eql(u8, uf.name, @tagName(tag))) {
                    tag_type = uf.type;
                    break;
                }
            }

            const ctag = std.meta.intToEnum(tag_type, ev.ev.code) catch
                @as(tag_type, @enumFromInt(0));

            const u = @unionInit(EventCode, @tagName(tag), ctag);
            break :fuk u;
        },
    };

    ev.type = et;
    ev.code = ec;
    ev.value = ev.ev.value;

    return switch (result) {
        c.LIBEVDEV_READ_STATUS_SYNC => .sync,
        c.LIBEVDEV_READ_STATUS_SUCCESS => .success,
        else => unreachable,
    };
}

// =============================================================
//                       UINPUT
// =============================================================

pub const UInput = struct {
    uifd: ?std.fs.File,
    uidev: *c.struct_libevdev_uinput,

    pub fn init(dev: *c.struct_libevdev, uinput_fd: ?std.fs.File) !UInput {
        const fd = if (uinput_fd) |uf| uf.handle else c.LIBEVDEV_UINPUT_OPEN_MANAGED;

        var ret: UInput = .{
            .uifd = uinput_fd,
            .uidev = undefined,
        };

        const result = c.libevdev_uinput_create_from_device(dev, fd, &ret.uidev);
        if (result != 0) return error.FailedToInitUinput;

        return ret;
    }

    pub fn deinit(self: *UInput) void {
        defer if (self.uifd) |uf| uf.close();
        defer c.libevdev_uinput_destroy(self.uidev);
    }

    pub const UInputInfo = enum {
        fd,
        syspath,
        devnode,
    };

    pub fn get(self: *UInput, comptime info: UInputInfo) switch (info) {
        .fd => i32,
        .devnode, .syspath => []const u8,
    } {
        return switch (info) {
            .fd => c.libevdev_uinput_get_fd(self.uidev),
            .devnode => std.mem.sliceTo(c.libevdev_uinput_get_devnode(self.uidev), 0),
            .syspath => std.mem.sliceTo(c.libevdev_uinput_get_syspath(self.uidev), 0),
        };
    }

    pub fn writeEvent(self: *UInput, event: InputEvent) !void {
        const code_num: i32 = switch (event.code) {
            .pwr, .max, .cnt, .version, .ff_status => |i| i,
            inline else => |e| @intFromEnum(e),
        };
        const write_result = c.libevdev_uinput_write_event(
            self.uidev,
            @intFromEnum(event.type),
            @intCast(code_num),
            event.value,
        );
        if (write_result != 0) return error.FailedToWriteEvent;

        const sync_result = c.libevdev_uinput_write_event(
            self.uidev,
            @intFromEnum(EventType.syn),
            @intFromEnum(events.SYN.REPORT),
            0,
        );
        if (sync_result != 0) return error.FailedToSyncEvent;
    }
};
