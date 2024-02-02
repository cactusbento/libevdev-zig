# libevdev-zig

Zig version: `0.12.0-dev.2536+788a0409a`

A Zig wrapper for `libevdev/libvbevdev.h` that covers the most useful functionalities of the library.

## Example

See `src/main.zig` for an example of the library in use.

## Modules

* `"libevdev"` - The wrapper itself. Covers mostly keyboards, may cover mouse.
  - Links `libc`
  - Links `libevdev`
    - Preferred link mode is `.Dynamic`

## Todo

* Cover API for the rest of the devices.
