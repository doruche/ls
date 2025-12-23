const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ls",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const install_action = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_action.step);

    const run_action = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_action.addArgs(args);
    }
    run_action.step.dependOn(&install_action.step);
    const run_step = b.step("run", "");
    run_step.dependOn(&run_action.step);

    const check_exe = b.addExecutable(.{
        .name = "__zls_check",
        .root_module = exe.root_module,
    });
    const check_step = b.step("check", "zls check");
    check_step.dependOn(&check_exe.step);
}

const stdout = std.fs.File.stdout();
var iobuf: [1024]u8 = undefined;
var writer = stdout.writer(iobuf[0..]);
const printer = &writer.interface;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const trait = arena.allocator();
    defer arena.deinit();
    const args = try std.process.argsAlloc(trait);
    defer std.process.argsFree(trait, args);

    if (args.len == 2 and std.mem.eql(u8, args[1], "-h")) {
        std.debug.print("usage: ls [path] [...]\n", .{});
        return;
    }

    const npaths = if (args.len >= 2) args.len - 1 else 1;
    var paths = try std.ArrayList([]const u8).initCapacity(trait, npaths);

    if (args.len >= 2) {
        try paths.appendSlice(trait, args[1..]);
    } else {
        try paths.append(trait, ".");
    }

    var dirs = try std.ArrayList([]const u8).initCapacity(trait, npaths);
    defer dirs.deinit(trait);

    for (paths.items) |path| {
        const abs_path = try std.fs.realpathAlloc(trait, path);
        defer trait.free(abs_path);
        const stat = try std.fs.cwd().statFile(abs_path);
        switch (stat.kind) {
            .directory => {
                // clone an absolute path to dirs
                const cloned = try trait.dupe(u8, abs_path);
                try dirs.append(trait, cloned);
            },
            else => {
                try printer.print("{s} ", .{path});
            },
        }
    }

    if (dirs.items.len > 0 and paths.items.len - dirs.items.len > 0) {
        try printer.print("\n", .{});
    }
    for (dirs.items) |dir| {
        defer trait.free(dir);

        if (dirs.items.len > 1) {
            try printer.print("{s}:\n", .{dir});
        }

        var d = try std.fs.openDirAbsolute(dir, .{ .iterate = true });
        defer d.close();
        var it: std.fs.Dir.Iterator = d.iterate();
        while (try it.next()) |dirent| {
            try printer.print("{s} ", .{dirent.name});
        }
        try printer.print("\n", .{});
    }

    try printer.flush();
    return;
}
