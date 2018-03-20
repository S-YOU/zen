use @import("multiboot.zig");
use @import("syscall.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const mem = @import("mem.zig");
const pmem = @import("pmem.zig");
const vmem = @import("vmem.zig");
const scheduler = @import("scheduler.zig");
const tty = @import("tty.zig");
const x86 = @import("x86.zig");
const timer = @import("timer.zig");
const std = @import("std");
const assert = std.debug.assert;
const Color = tty.Color;

////
// Panic function called by Zig on language errors.
//
// Arguments:
//     message: Reason for the panic.
//
pub var kernel_multiboot_module: ?&MultibootModule = null;
pub fn panic(message: []const u8, error_return_trace: ?&@import("builtin").StackTrace) noreturn {
    tty.writeChar('\n');

    tty.setBackground(Color.Red);
    tty.colorPrintf(Color.White, "KERNEL PANIC: {}\n", message);

    if (kernel_multiboot_module) |kmod| {
        const elf_file_ptr = @intToPtr(&u8, kmod.mod_start);
        var elf_file = std.io.FixedBufferSeekableStream.init(elf_file_ptr[0.. kmod.mod_end - kmod.mod_start]);
        var tty_out_stream = std.io.OutStream(error) { .writeFn = ttyWriteFn };
        var debug_info = std.debug.openDebugInfo(std.debug.global_allocator, &elf_file.stream) catch |e| {
            tty.printf("unable to dump stack trace: unable to open kernel debug info: {}\n", e);
            x86.hang();
        };
        std.debug.writeCurrentStackTrace(&tty_out_stream, std.debug.global_allocator, debug_info, true, null) catch |e| {
            tty.printf("unable to dump stack trace: {}\n", e);
            x86.hang();
        };
    } else {
        tty.write("panic occurred before kernel ELF/DWARF info was available\n");
    }

    x86.hang();
}

fn ttyWriteFn(outstream: &std.io.OutStream(error), bytes: []const u8) error!void {
    tty.write(bytes);
}

////
// Get the ball rolling.
//
// Arguments:
//     magic: Magic number from bootloader.
//     info: Information structure from bootloader.
//
export fn kmain(magic: u32, info: &const MultibootInfo) noreturn {
    tty.initialize();

    assert (magic == MULTIBOOT_BOOTLOADER_MAGIC);

    const title = "Zen - v0.0.1";
    tty.alignCenter(title.len);
    tty.colorPrintf(Color.LightRed, title ++ "\n\n");

    tty.colorPrintf(Color.LightBlue, "Booting the microkernel:\n");
    gdt.initialize();
    idt.initialize();
    pmem.initialize(info);
    vmem.initialize();
    mem.initialize(0x10000);
    timer.initialize(100);
    scheduler.initialize();

    tty.colorPrintf(Color.LightBlue, "\nLoading the servers:\n");
    info.loadModules();

    x86.sti();
    x86.hlt();
}
