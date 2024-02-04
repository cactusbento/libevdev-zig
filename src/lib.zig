const std = @import("std");
const c = @import("translate-c/libevdev-uinput.zig");

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

pub const EventType = enum(i32) {
    syn = c.EV_SYN,
    rel = c.EV_REL,
    sw = c.EV_SW,
    ff = c.EV_FF,
    key = c.EV_KEY,
    abs = c.EV_ABS,
    msc = c.EV_MSC,
    led = c.EV_LED,
    snd = c.EV_SND,
    rep = c.EV_REP,
    pwr = c.EV_PWR,
    max = c.EV_MAX,
    cnt = c.EV_CNT,
    version = c.EV_VERSION,
    ff_status = c.EV_FF_STATUS,
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
    code: u32,
    value: i32,

    pub fn string(self: *InputEvent, field: enum { type, code }) []const u8 {
        return switch (field) {
            .type => std.mem.sliceTo(c.libevdev_event_type_get_name(self.ev.type), 0),
            .code => std.mem.sliceTo(c.libevdev_event_code_get_name(self.ev.type, self.code), 0),
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

    ev.type = @enumFromInt(ev.ev.type);
    ev.value = ev.ev.value;
    ev.code = ev.ev.code;

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
        const result = c.libevdev_uinput_write_event(
            self.uidevm,
            @intFromEnum(event.type),
            event.code,
            event.value,
        );
        if (result != 0) return error.FailedToWriteEvent;
    }
};

pub const key = struct {
    pub const RESERVED = @as(c_int, 0);
    pub const ESC = @as(c_int, 1);
    pub const @"1" = @as(c_int, 2);
    pub const @"2" = @as(c_int, 3);
    pub const @"3" = @as(c_int, 4);
    pub const @"4" = @as(c_int, 5);
    pub const @"5" = @as(c_int, 6);
    pub const @"6" = @as(c_int, 7);
    pub const @"7" = @as(c_int, 8);
    pub const @"8" = @as(c_int, 9);
    pub const @"9" = @as(c_int, 10);
    pub const @"0" = @as(c_int, 11);
    pub const MINUS = @as(c_int, 12);
    pub const EQUAL = @as(c_int, 13);
    pub const BACKSPACE = @as(c_int, 14);
    pub const TAB = @as(c_int, 15);
    pub const Q = @as(c_int, 16);
    pub const W = @as(c_int, 17);
    pub const E = @as(c_int, 18);
    pub const R = @as(c_int, 19);
    pub const T = @as(c_int, 20);
    pub const Y = @as(c_int, 21);
    pub const U = @as(c_int, 22);
    pub const I = @as(c_int, 23);
    pub const O = @as(c_int, 24);
    pub const P = @as(c_int, 25);
    pub const LEFTBRACE = @as(c_int, 26);
    pub const RIGHTBRACE = @as(c_int, 27);
    pub const ENTER = @as(c_int, 28);
    pub const LEFTCTRL = @as(c_int, 29);
    pub const A = @as(c_int, 30);
    pub const S = @as(c_int, 31);
    pub const D = @as(c_int, 32);
    pub const F = @as(c_int, 33);
    pub const G = @as(c_int, 34);
    pub const H = @as(c_int, 35);
    pub const J = @as(c_int, 36);
    pub const K = @as(c_int, 37);
    pub const L = @as(c_int, 38);
    pub const SEMICOLON = @as(c_int, 39);
    pub const APOSTROPHE = @as(c_int, 40);
    pub const GRAVE = @as(c_int, 41);
    pub const LEFTSHIFT = @as(c_int, 42);
    pub const BACKSLASH = @as(c_int, 43);
    pub const Z = @as(c_int, 44);
    pub const X = @as(c_int, 45);
    pub const C = @as(c_int, 46);
    pub const V = @as(c_int, 47);
    pub const B = @as(c_int, 48);
    pub const N = @as(c_int, 49);
    pub const M = @as(c_int, 50);
    pub const COMMA = @as(c_int, 51);
    pub const DOT = @as(c_int, 52);
    pub const SLASH = @as(c_int, 53);
    pub const RIGHTSHIFT = @as(c_int, 54);
    pub const KPASTERISK = @as(c_int, 55);
    pub const LEFTALT = @as(c_int, 56);
    pub const SPACE = @as(c_int, 57);
    pub const CAPSLOCK = @as(c_int, 58);
    pub const F1 = @as(c_int, 59);
    pub const F2 = @as(c_int, 60);
    pub const F3 = @as(c_int, 61);
    pub const F4 = @as(c_int, 62);
    pub const F5 = @as(c_int, 63);
    pub const F6 = @as(c_int, 64);
    pub const F7 = @as(c_int, 65);
    pub const F8 = @as(c_int, 66);
    pub const F9 = @as(c_int, 67);
    pub const F10 = @as(c_int, 68);
    pub const NUMLOCK = @as(c_int, 69);
    pub const SCROLLLOCK = @as(c_int, 70);
    pub const KP7 = @as(c_int, 71);
    pub const KP8 = @as(c_int, 72);
    pub const KP9 = @as(c_int, 73);
    pub const KPMINUS = @as(c_int, 74);
    pub const KP4 = @as(c_int, 75);
    pub const KP5 = @as(c_int, 76);
    pub const KP6 = @as(c_int, 77);
    pub const KPPLUS = @as(c_int, 78);
    pub const KP1 = @as(c_int, 79);
    pub const KP2 = @as(c_int, 80);
    pub const KP3 = @as(c_int, 81);
    pub const KP0 = @as(c_int, 82);
    pub const KPDOT = @as(c_int, 83);
    pub const ZENKAKUHANKAKU = @as(c_int, 85);
    pub const @"102ND" = @as(c_int, 86);
    pub const F11 = @as(c_int, 87);
    pub const F12 = @as(c_int, 88);
    pub const RO = @as(c_int, 89);
    pub const KATAKANA = @as(c_int, 90);
    pub const HIRAGANA = @as(c_int, 91);
    pub const HENKAN = @as(c_int, 92);
    pub const KATAKANAHIRAGANA = @as(c_int, 93);
    pub const MUHENKAN = @as(c_int, 94);
    pub const KPJPCOMMA = @as(c_int, 95);
    pub const KPENTER = @as(c_int, 96);
    pub const RIGHTCTRL = @as(c_int, 97);
    pub const KPSLASH = @as(c_int, 98);
    pub const SYSRQ = @as(c_int, 99);
    pub const RIGHTALT = @as(c_int, 100);
    pub const LINEFEED = @as(c_int, 101);
    pub const HOME = @as(c_int, 102);
    pub const UP = @as(c_int, 103);
    pub const PAGEUP = @as(c_int, 104);
    pub const LEFT = @as(c_int, 105);
    pub const RIGHT = @as(c_int, 106);
    pub const END = @as(c_int, 107);
    pub const DOWN = @as(c_int, 108);
    pub const PAGEDOWN = @as(c_int, 109);
    pub const INSERT = @as(c_int, 110);
    pub const DELETE = @as(c_int, 111);
    pub const MACRO = @as(c_int, 112);
    pub const MUTE = @as(c_int, 113);
    pub const VOLUMEDOWN = @as(c_int, 114);
    pub const VOLUMEUP = @as(c_int, 115);
    pub const POWER = @as(c_int, 116);
    pub const KPEQUAL = @as(c_int, 117);
    pub const KPPLUSMINUS = @as(c_int, 118);
    pub const PAUSE = @as(c_int, 119);
    pub const SCALE = @as(c_int, 120);
    pub const KPCOMMA = @as(c_int, 121);
    pub const HANGEUL = @as(c_int, 122);
    pub const HANGUEL = HANGEUL;
    pub const HANJA = @as(c_int, 123);
    pub const YEN = @as(c_int, 124);
    pub const LEFTMETA = @as(c_int, 125);
    pub const RIGHTMETA = @as(c_int, 126);
    pub const COMPOSE = @as(c_int, 127);
    pub const STOP = @as(c_int, 128);
    pub const AGAIN = @as(c_int, 129);
    pub const PROPS = @as(c_int, 130);
    pub const UNDO = @as(c_int, 131);
    pub const FRONT = @as(c_int, 132);
    pub const COPY = @as(c_int, 133);
    pub const OPEN = @as(c_int, 134);
    pub const PASTE = @as(c_int, 135);
    pub const FIND = @as(c_int, 136);
    pub const CUT = @as(c_int, 137);
    pub const HELP = @as(c_int, 138);
    pub const MENU = @as(c_int, 139);
    pub const CALC = @as(c_int, 140);
    pub const SETUP = @as(c_int, 141);
    pub const SLEEP = @as(c_int, 142);
    pub const WAKEUP = @as(c_int, 143);
    pub const FILE = @as(c_int, 144);
    pub const SENDFILE = @as(c_int, 145);
    pub const DELETEFILE = @as(c_int, 146);
    pub const XFER = @as(c_int, 147);
    pub const PROG1 = @as(c_int, 148);
    pub const PROG2 = @as(c_int, 149);
    pub const WWW = @as(c_int, 150);
    pub const MSDOS = @as(c_int, 151);
    pub const COFFEE = @as(c_int, 152);
    pub const SCREENLOCK = COFFEE;
    pub const ROTATE_DISPLAY = @as(c_int, 153);
    pub const DIRECTION = ROTATE_DISPLAY;
    pub const CYCLEWINDOWS = @as(c_int, 154);
    pub const MAIL = @as(c_int, 155);
    pub const BOOKMARKS = @as(c_int, 156);
    pub const COMPUTER = @as(c_int, 157);
    pub const BACK = @as(c_int, 158);
    pub const FORWARD = @as(c_int, 159);
    pub const CLOSECD = @as(c_int, 160);
    pub const EJECTCD = @as(c_int, 161);
    pub const EJECTCLOSECD = @as(c_int, 162);
    pub const NEXTSONG = @as(c_int, 163);
    pub const PLAYPAUSE = @as(c_int, 164);
    pub const PREVIOUSSONG = @as(c_int, 165);
    pub const STOPCD = @as(c_int, 166);
    pub const RECORD = @as(c_int, 167);
    pub const REWIND = @as(c_int, 168);
    pub const PHONE = @as(c_int, 169);
    pub const ISO = @as(c_int, 170);
    pub const CONFIG = @as(c_int, 171);
    pub const HOMEPAGE = @as(c_int, 172);
    pub const REFRESH = @as(c_int, 173);
    pub const EXIT = @as(c_int, 174);
    pub const MOVE = @as(c_int, 175);
    pub const EDIT = @as(c_int, 176);
    pub const SCROLLUP = @as(c_int, 177);
    pub const SCROLLDOWN = @as(c_int, 178);
    pub const KPLEFTPAREN = @as(c_int, 179);
    pub const KPRIGHTPAREN = @as(c_int, 180);
    pub const NEW = @as(c_int, 181);
    pub const REDO = @as(c_int, 182);
    pub const F13 = @as(c_int, 183);
    pub const F14 = @as(c_int, 184);
    pub const F15 = @as(c_int, 185);
    pub const F16 = @as(c_int, 186);
    pub const F17 = @as(c_int, 187);
    pub const F18 = @as(c_int, 188);
    pub const F19 = @as(c_int, 189);
    pub const F20 = @as(c_int, 190);
    pub const F21 = @as(c_int, 191);
    pub const F22 = @as(c_int, 192);
    pub const F23 = @as(c_int, 193);
    pub const F24 = @as(c_int, 194);
    pub const PLAYCD = @as(c_int, 200);
    pub const PAUSECD = @as(c_int, 201);
    pub const PROG3 = @as(c_int, 202);
    pub const PROG4 = @as(c_int, 203);
    pub const ALL_APPLICATIONS = @as(c_int, 204);
    pub const DASHBOARD = ALL_APPLICATIONS;
    pub const SUSPEND = @as(c_int, 205);
    pub const CLOSE = @as(c_int, 206);
    pub const PLAY = @as(c_int, 207);
    pub const FASTFORWARD = @as(c_int, 208);
    pub const BASSBOOST = @as(c_int, 209);
    pub const PRINT = @as(c_int, 210);
    pub const HP = @as(c_int, 211);
    pub const CAMERA = @as(c_int, 212);
    pub const SOUND = @as(c_int, 213);
    pub const QUESTION = @as(c_int, 214);
    pub const EMAIL = @as(c_int, 215);
    pub const CHAT = @as(c_int, 216);
    pub const SEARCH = @as(c_int, 217);
    pub const CONNECT = @as(c_int, 218);
    pub const FINANCE = @as(c_int, 219);
    pub const SPORT = @as(c_int, 220);
    pub const SHOP = @as(c_int, 221);
    pub const ALTERASE = @as(c_int, 222);
    pub const CANCEL = @as(c_int, 223);
    pub const BRIGHTNESSDOWN = @as(c_int, 224);
    pub const BRIGHTNESSUP = @as(c_int, 225);
    pub const MEDIA = @as(c_int, 226);
    pub const SWITCHVIDEOMODE = @as(c_int, 227);
    pub const KBDILLUMTOGGLE = @as(c_int, 228);
    pub const KBDILLUMDOWN = @as(c_int, 229);
    pub const KBDILLUMUP = @as(c_int, 230);
    pub const SEND = @as(c_int, 231);
    pub const REPLY = @as(c_int, 232);
    pub const FORWARDMAIL = @as(c_int, 233);
    pub const SAVE = @as(c_int, 234);
    pub const DOCUMENTS = @as(c_int, 235);
    pub const BATTERY = @as(c_int, 236);
    pub const BLUETOOTH = @as(c_int, 237);
    pub const WLAN = @as(c_int, 238);
    pub const UWB = @as(c_int, 239);
    pub const UNKNOWN = @as(c_int, 240);
    pub const VIDEO_NEXT = @as(c_int, 241);
    pub const VIDEO_PREV = @as(c_int, 242);
    pub const BRIGHTNESS_CYCLE = @as(c_int, 243);
    pub const BRIGHTNESS_AUTO = @as(c_int, 244);
    pub const BRIGHTNESS_ZERO = BRIGHTNESS_AUTO;
    pub const DISPLAY_OFF = @as(c_int, 245);
    pub const WWAN = @as(c_int, 246);
    pub const WIMAX = WWAN;
    pub const RFKILL = @as(c_int, 247);
    pub const MICMUTE = @as(c_int, 248);
    pub const OK = @as(c_int, 0x160);
    pub const SELECT = @as(c_int, 0x161);
    pub const GOTO = @as(c_int, 0x162);
    pub const CLEAR = @as(c_int, 0x163);
    pub const POWER2 = @as(c_int, 0x164);
    pub const OPTION = @as(c_int, 0x165);
    pub const INFO = @as(c_int, 0x166);
    pub const TIME = @as(c_int, 0x167);
    pub const VENDOR = @as(c_int, 0x168);
    pub const ARCHIVE = @as(c_int, 0x169);
    pub const PROGRAM = @as(c_int, 0x16a);
    pub const CHANNEL = @as(c_int, 0x16b);
    pub const FAVORITES = @as(c_int, 0x16c);
    pub const EPG = @as(c_int, 0x16d);
    pub const PVR = @as(c_int, 0x16e);
    pub const MHP = @as(c_int, 0x16f);
    pub const LANGUAGE = @as(c_int, 0x170);
    pub const TITLE = @as(c_int, 0x171);
    pub const SUBTITLE = @as(c_int, 0x172);
    pub const ANGLE = @as(c_int, 0x173);
    pub const FULL_SCREEN = @as(c_int, 0x174);
    pub const ZOOM = FULL_SCREEN;
    pub const MODE = @as(c_int, 0x175);
    pub const KEYBOARD = @as(c_int, 0x176);
    pub const ASPECT_RATIO = @as(c_int, 0x177);
    pub const SCREEN = ASPECT_RATIO;
    pub const PC = @as(c_int, 0x178);
    pub const TV = @as(c_int, 0x179);
    pub const TV2 = @as(c_int, 0x17a);
    pub const VCR = @as(c_int, 0x17b);
    pub const VCR2 = @as(c_int, 0x17c);
    pub const SAT = @as(c_int, 0x17d);
    pub const SAT2 = @as(c_int, 0x17e);
    pub const CD = @as(c_int, 0x17f);
    pub const TAPE = @as(c_int, 0x180);
    pub const RADIO = @as(c_int, 0x181);
    pub const TUNER = @as(c_int, 0x182);
    pub const PLAYER = @as(c_int, 0x183);
    pub const TEXT = @as(c_int, 0x184);
    pub const DVD = @as(c_int, 0x185);
    pub const AUX = @as(c_int, 0x186);
    pub const MP3 = @as(c_int, 0x187);
    pub const AUDIO = @as(c_int, 0x188);
    pub const VIDEO = @as(c_int, 0x189);
    pub const DIRECTORY = @as(c_int, 0x18a);
    pub const LIST = @as(c_int, 0x18b);
    pub const MEMO = @as(c_int, 0x18c);
    pub const CALENDAR = @as(c_int, 0x18d);
    pub const RED = @as(c_int, 0x18e);
    pub const GREEN = @as(c_int, 0x18f);
    pub const YELLOW = @as(c_int, 0x190);
    pub const BLUE = @as(c_int, 0x191);
    pub const CHANNELUP = @as(c_int, 0x192);
    pub const CHANNELDOWN = @as(c_int, 0x193);
    pub const FIRST = @as(c_int, 0x194);
    pub const LAST = @as(c_int, 0x195);
    pub const AB = @as(c_int, 0x196);
    pub const NEXT = @as(c_int, 0x197);
    pub const RESTART = @as(c_int, 0x198);
    pub const SLOW = @as(c_int, 0x199);
    pub const SHUFFLE = @as(c_int, 0x19a);
    pub const BREAK = @as(c_int, 0x19b);
    pub const PREVIOUS = @as(c_int, 0x19c);
    pub const DIGITS = @as(c_int, 0x19d);
    pub const TEEN = @as(c_int, 0x19e);
    pub const TWEN = @as(c_int, 0x19f);
    pub const VIDEOPHONE = @as(c_int, 0x1a0);
    pub const GAMES = @as(c_int, 0x1a1);
    pub const ZOOMIN = @as(c_int, 0x1a2);
    pub const ZOOMOUT = @as(c_int, 0x1a3);
    pub const ZOOMRESET = @as(c_int, 0x1a4);
    pub const WORDPROCESSOR = @as(c_int, 0x1a5);
    pub const EDITOR = @as(c_int, 0x1a6);
    pub const SPREADSHEET = @as(c_int, 0x1a7);
    pub const GRAPHICSEDITOR = @as(c_int, 0x1a8);
    pub const PRESENTATION = @as(c_int, 0x1a9);
    pub const DATABASE = @as(c_int, 0x1aa);
    pub const NEWS = @as(c_int, 0x1ab);
    pub const VOICEMAIL = @as(c_int, 0x1ac);
    pub const ADDRESSBOOK = @as(c_int, 0x1ad);
    pub const MESSENGER = @as(c_int, 0x1ae);
    pub const DISPLAYTOGGLE = @as(c_int, 0x1af);
    pub const BRIGHTNESS_TOGGLE = DISPLAYTOGGLE;
    pub const SPELLCHECK = @as(c_int, 0x1b0);
    pub const LOGOFF = @as(c_int, 0x1b1);
    pub const DOLLAR = @as(c_int, 0x1b2);
    pub const EURO = @as(c_int, 0x1b3);
    pub const FRAMEBACK = @as(c_int, 0x1b4);
    pub const FRAMEFORWARD = @as(c_int, 0x1b5);
    pub const CONTEXT_MENU = @as(c_int, 0x1b6);
    pub const MEDIA_REPEAT = @as(c_int, 0x1b7);
    pub const @"10CHANNELSUP" = @as(c_int, 0x1b8);
    pub const @"10CHANNELSDOWN" = @as(c_int, 0x1b9);
    pub const IMAGES = @as(c_int, 0x1ba);
    pub const NOTIFICATION_CENTER = @as(c_int, 0x1bc);
    pub const PICKUP_PHONE = @as(c_int, 0x1bd);
    pub const HANGUP_PHONE = @as(c_int, 0x1be);
    pub const DEL_EOL = @as(c_int, 0x1c0);
    pub const DEL_EOS = @as(c_int, 0x1c1);
    pub const INS_LINE = @as(c_int, 0x1c2);
    pub const DEL_LINE = @as(c_int, 0x1c3);
    pub const FN = @as(c_int, 0x1d0);
    pub const FN_ESC = @as(c_int, 0x1d1);
    pub const FN_F1 = @as(c_int, 0x1d2);
    pub const FN_F2 = @as(c_int, 0x1d3);
    pub const FN_F3 = @as(c_int, 0x1d4);
    pub const FN_F4 = @as(c_int, 0x1d5);
    pub const FN_F5 = @as(c_int, 0x1d6);
    pub const FN_F6 = @as(c_int, 0x1d7);
    pub const FN_F7 = @as(c_int, 0x1d8);
    pub const FN_F8 = @as(c_int, 0x1d9);
    pub const FN_F9 = @as(c_int, 0x1da);
    pub const FN_F10 = @as(c_int, 0x1db);
    pub const FN_F11 = @as(c_int, 0x1dc);
    pub const FN_F12 = @as(c_int, 0x1dd);
    pub const FN_1 = @as(c_int, 0x1de);
    pub const FN_2 = @as(c_int, 0x1df);
    pub const FN_D = @as(c_int, 0x1e0);
    pub const FN_E = @as(c_int, 0x1e1);
    pub const FN_F = @as(c_int, 0x1e2);
    pub const FN_S = @as(c_int, 0x1e3);
    pub const FN_B = @as(c_int, 0x1e4);
    pub const FN_RIGHT_SHIFT = @as(c_int, 0x1e5);
    pub const BRL_DOT1 = @as(c_int, 0x1f1);
    pub const BRL_DOT2 = @as(c_int, 0x1f2);
    pub const BRL_DOT3 = @as(c_int, 0x1f3);
    pub const BRL_DOT4 = @as(c_int, 0x1f4);
    pub const BRL_DOT5 = @as(c_int, 0x1f5);
    pub const BRL_DOT6 = @as(c_int, 0x1f6);
    pub const BRL_DOT7 = @as(c_int, 0x1f7);
    pub const BRL_DOT8 = @as(c_int, 0x1f8);
    pub const BRL_DOT9 = @as(c_int, 0x1f9);
    pub const BRL_DOT10 = @as(c_int, 0x1fa);
    pub const NUMERIC_0 = @as(c_int, 0x200);
    pub const NUMERIC_1 = @as(c_int, 0x201);
    pub const NUMERIC_2 = @as(c_int, 0x202);
    pub const NUMERIC_3 = @as(c_int, 0x203);
    pub const NUMERIC_4 = @as(c_int, 0x204);
    pub const NUMERIC_5 = @as(c_int, 0x205);
    pub const NUMERIC_6 = @as(c_int, 0x206);
    pub const NUMERIC_7 = @as(c_int, 0x207);
    pub const NUMERIC_8 = @as(c_int, 0x208);
    pub const NUMERIC_9 = @as(c_int, 0x209);
    pub const NUMERIC_STAR = @as(c_int, 0x20a);
    pub const NUMERIC_POUND = @as(c_int, 0x20b);
    pub const NUMERIC_A = @as(c_int, 0x20c);
    pub const NUMERIC_B = @as(c_int, 0x20d);
    pub const NUMERIC_C = @as(c_int, 0x20e);
    pub const NUMERIC_D = @as(c_int, 0x20f);
    pub const CAMERA_FOCUS = @as(c_int, 0x210);
    pub const WPS_BUTTON = @as(c_int, 0x211);
    pub const TOUCHPAD_TOGGLE = @as(c_int, 0x212);
    pub const TOUCHPAD_ON = @as(c_int, 0x213);
    pub const TOUCHPAD_OFF = @as(c_int, 0x214);
    pub const CAMERA_ZOOMIN = @as(c_int, 0x215);
    pub const CAMERA_ZOOMOUT = @as(c_int, 0x216);
    pub const CAMERA_UP = @as(c_int, 0x217);
    pub const CAMERA_DOWN = @as(c_int, 0x218);
    pub const CAMERA_LEFT = @as(c_int, 0x219);
    pub const CAMERA_RIGHT = @as(c_int, 0x21a);
    pub const ATTENDANT_ON = @as(c_int, 0x21b);
    pub const ATTENDANT_OFF = @as(c_int, 0x21c);
    pub const ATTENDANT_TOGGLE = @as(c_int, 0x21d);
    pub const LIGHTS_TOGGLE = @as(c_int, 0x21e);
    pub const ALS_TOGGLE = @as(c_int, 0x230);
    pub const ROTATE_LOCK_TOGGLE = @as(c_int, 0x231);
    pub const BUTTONCONFIG = @as(c_int, 0x240);
    pub const TASKMANAGER = @as(c_int, 0x241);
    pub const JOURNAL = @as(c_int, 0x242);
    pub const CONTROLPANEL = @as(c_int, 0x243);
    pub const APPSELECT = @as(c_int, 0x244);
    pub const SCREENSAVER = @as(c_int, 0x245);
    pub const VOICECOMMAND = @as(c_int, 0x246);
    pub const ASSISTANT = @as(c_int, 0x247);
    pub const KBD_LAYOUT_NEXT = @as(c_int, 0x248);
    pub const EMOJI_PICKER = @as(c_int, 0x249);
    pub const DICTATE = @as(c_int, 0x24a);
    pub const CAMERA_ACCESS_ENABLE = @as(c_int, 0x24b);
    pub const CAMERA_ACCESS_DISABLE = @as(c_int, 0x24c);
    pub const CAMERA_ACCESS_TOGGLE = @as(c_int, 0x24d);
    pub const BRIGHTNESS_MIN = @as(c_int, 0x250);
    pub const BRIGHTNESS_MAX = @as(c_int, 0x251);
    pub const KBDINPUTASSIST_PREV = @as(c_int, 0x260);
    pub const KBDINPUTASSIST_NEXT = @as(c_int, 0x261);
    pub const KBDINPUTASSIST_PREVGROUP = @as(c_int, 0x262);
    pub const KBDINPUTASSIST_NEXTGROUP = @as(c_int, 0x263);
    pub const KBDINPUTASSIST_ACCEPT = @as(c_int, 0x264);
    pub const KBDINPUTASSIST_CANCEL = @as(c_int, 0x265);
    pub const RIGHT_UP = @as(c_int, 0x266);
    pub const RIGHT_DOWN = @as(c_int, 0x267);
    pub const LEFT_UP = @as(c_int, 0x268);
    pub const LEFT_DOWN = @as(c_int, 0x269);
    pub const ROOT_MENU = @as(c_int, 0x26a);
    pub const MEDIA_TOP_MENU = @as(c_int, 0x26b);
    pub const NUMERIC_11 = @as(c_int, 0x26c);
    pub const NUMERIC_12 = @as(c_int, 0x26d);
    pub const AUDIO_DESC = @as(c_int, 0x26e);
    pub const @"3D_MODE" = @as(c_int, 0x26f);
    pub const NEXT_FAVORITE = @as(c_int, 0x270);
    pub const STOP_RECORD = @as(c_int, 0x271);
    pub const PAUSE_RECORD = @as(c_int, 0x272);
    pub const VOD = @as(c_int, 0x273);
    pub const UNMUTE = @as(c_int, 0x274);
    pub const FASTREVERSE = @as(c_int, 0x275);
    pub const SLOWREVERSE = @as(c_int, 0x276);
    pub const DATA = @as(c_int, 0x277);
    pub const ONSCREEN_KEYBOARD = @as(c_int, 0x278);
    pub const PRIVACY_SCREEN_TOGGLE = @as(c_int, 0x279);
    pub const SELECTIVE_SCREENSHOT = @as(c_int, 0x27a);
    pub const NEXT_ELEMENT = @as(c_int, 0x27b);
    pub const PREVIOUS_ELEMENT = @as(c_int, 0x27c);
    pub const AUTOPILOT_ENGAGE_TOGGLE = @as(c_int, 0x27d);
    pub const MARK_WAYPOINT = @as(c_int, 0x27e);
    pub const SOS = @as(c_int, 0x27f);
    pub const NAV_CHART = @as(c_int, 0x280);
    pub const FISHING_CHART = @as(c_int, 0x281);
    pub const SINGLE_RANGE_RADAR = @as(c_int, 0x282);
    pub const DUAL_RANGE_RADAR = @as(c_int, 0x283);
    pub const RADAR_OVERLAY = @as(c_int, 0x284);
    pub const TRADITIONAL_SONAR = @as(c_int, 0x285);
    pub const CLEARVU_SONAR = @as(c_int, 0x286);
    pub const SIDEVU_SONAR = @as(c_int, 0x287);
    pub const NAV_INFO = @as(c_int, 0x288);
    pub const BRIGHTNESS_MENU = @as(c_int, 0x289);
    pub const MACRO1 = @as(c_int, 0x290);
    pub const MACRO2 = @as(c_int, 0x291);
    pub const MACRO3 = @as(c_int, 0x292);
    pub const MACRO4 = @as(c_int, 0x293);
    pub const MACRO5 = @as(c_int, 0x294);
    pub const MACRO6 = @as(c_int, 0x295);
    pub const MACRO7 = @as(c_int, 0x296);
    pub const MACRO8 = @as(c_int, 0x297);
    pub const MACRO9 = @as(c_int, 0x298);
    pub const MACRO10 = @as(c_int, 0x299);
    pub const MACRO11 = @as(c_int, 0x29a);
    pub const MACRO12 = @as(c_int, 0x29b);
    pub const MACRO13 = @as(c_int, 0x29c);
    pub const MACRO14 = @as(c_int, 0x29d);
    pub const MACRO15 = @as(c_int, 0x29e);
    pub const MACRO16 = @as(c_int, 0x29f);
    pub const MACRO17 = @as(c_int, 0x2a0);
    pub const MACRO18 = @as(c_int, 0x2a1);
    pub const MACRO19 = @as(c_int, 0x2a2);
    pub const MACRO20 = @as(c_int, 0x2a3);
    pub const MACRO21 = @as(c_int, 0x2a4);
    pub const MACRO22 = @as(c_int, 0x2a5);
    pub const MACRO23 = @as(c_int, 0x2a6);
    pub const MACRO24 = @as(c_int, 0x2a7);
    pub const MACRO25 = @as(c_int, 0x2a8);
    pub const MACRO26 = @as(c_int, 0x2a9);
    pub const MACRO27 = @as(c_int, 0x2aa);
    pub const MACRO28 = @as(c_int, 0x2ab);
    pub const MACRO29 = @as(c_int, 0x2ac);
    pub const MACRO30 = @as(c_int, 0x2ad);
    pub const MACRO_RECORD_START = @as(c_int, 0x2b0);
    pub const MACRO_RECORD_STOP = @as(c_int, 0x2b1);
    pub const MACRO_PRESET_CYCLE = @as(c_int, 0x2b2);
    pub const MACRO_PRESET1 = @as(c_int, 0x2b3);
    pub const MACRO_PRESET2 = @as(c_int, 0x2b4);
    pub const MACRO_PRESET3 = @as(c_int, 0x2b5);
    pub const KBD_LCD_MENU1 = @as(c_int, 0x2b8);
    pub const KBD_LCD_MENU2 = @as(c_int, 0x2b9);
    pub const KBD_LCD_MENU3 = @as(c_int, 0x2ba);
    pub const KBD_LCD_MENU4 = @as(c_int, 0x2bb);
    pub const KBD_LCD_MENU5 = @as(c_int, 0x2bc);
    pub const MIN_INTERESTING = MUTE;
    pub const MAX = @as(c_int, 0x2ff);
    pub const CNT = MAX + @as(c_int, 1);
};
