const std = @import("std");

const default_erlang_home: []const u8 = "/usr/local/lib/erlang/erts-15.2.2/include";

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.

/// Defines build params
///
/// - `b`: the build params. The only custom build params that has to be passed after `--` is
/// the Erlang home.
/// Please refer to [this](https://stackoverflow.com/questions/72558202/can-i-pass-commandline-arguments-when-invoking-zig-build-run)
/// article for more information about passing build parameters.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "example_nif",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Including Erlang path for compilation.
    const erlang_home = getErlangHomeFromArguments(b.args);
    std.debug.print("Erlang home: '{s}'\n", .{erlang_home});

    lib.addIncludePath(.{ .cwd_relative = erlang_home });

    // Linking LibC for Erlang NIFs.
    lib.linkLibC();

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}

fn getErlangHomeFromArguments(args: ?[]const []const u8) []const u8 {
    if (args) |as| {
        return as[0];
    }

    return default_erlang_home;
}
