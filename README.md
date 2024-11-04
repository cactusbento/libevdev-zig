# libevdev-zig

Zig version: `0.14.0-dev.2162+3054486d1`

A Zig wrapper for `libevdev/libvbevdev.h` that covers the most useful functionalities of the library.

## Example

See `src/main.zig` for an example of the library in use.

## Modules

* `"libevdev"` - The wrapper itself. Covers mostly keyboards, may cover mice.
  - Links `libc`
  - Links `libevdev`
    - Preferred link mode is `.dynamic`

## Todo

* Cover API for the rest of the devices. (PRs welcome)
