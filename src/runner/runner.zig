const std = @import("std");
const sdl = @import("sdl");
const zgl = @import("zgl");

var was_init: bool = false;
var window: sdl.Window = undefined;
var glctx: sdl.gl.Context = undefined;

pub fn loop(game: anytype) !void {
    try init();
    defer deinit();

    try game.init();
    defer game.deinit();

    mainLoop: while (true) {
        while (sdl.pollNativeEvent()) |event| {
            if (event.type == sdl.c.SDL_QUIT)
                break :mainLoop;
        }

        try game.process();
        try game.frame();

        // todo: Make sure swapping doesn't block processing of the next frame.
        //       For that main thread might be delegated fully to rendering.
        sdl.gl.swapWindow(window);

        zgl.invalidateFramebuffer(.draw_buffer, &[_]zgl.FramebufferAttachment{ .default_color, .default_depth, .default_stencil });
        zgl.clear(.{ .depth = true, .stencil = true });
        zgl.flush();
    }
}

pub fn init() !void {
    if (was_init)
        return;

    sdl.c.SDL_SetMainReady();

    try sdl.init(.{ .video = true });

    window = try sdl.createWindow("sobbingSkies", .centered, .centered, 640, 480, .{ .context = .opengl });

    // try sdl.gl.setAttribute(.{ .context_profile_mask = .es });
    // try sdl.gl.setAttribute(.{ .context_major_version = 2 });
    // try sdl.gl.setAttribute(.{ .context_minor_version = 0 });
    try sdl.gl.setAttribute(.{ .doublebuffer = true });
    try sdl.gl.setAttribute(.{ .accelerated_visual = true });
    try sdl.gl.setAttribute(.{ .buffer_size = 24 });
    try sdl.gl.setAttribute(.{ .alpha_size = 0 });
    try sdl.gl.setAttribute(.{ .depth_size = 16 });
    try sdl.gl.setAttribute(.{ .stencil_size = 0 });
    try sdl.gl.setAttribute(.{ .accum_red_size = 0 });
    try sdl.gl.setAttribute(.{ .accum_green_size = 0 });
    try sdl.gl.setAttribute(.{ .accum_blue_size = 0 });
    try sdl.gl.setAttribute(.{ .accum_alpha_size = 0 });
    try sdl.gl.setAttribute(.{ .multisamplebuffers = false });

    try sdl.gl.setAttribute(.{
        .context_flags = .{
            .debug = comptime std.debug.runtime_safety,
            // .forward_compatible = true,
            // .robust_access = true,
        },
    });

    glctx = try sdl.gl.createContext(window);

    try zgl.loadExtensions({}, sdlLoadGlProcedure);

    zgl.viewport(0, 0, 640, 480);

    sdl.gl.setSwapInterval(.adaptive_vsync) catch sdl.gl.setSwapInterval(.vsync) catch try sdl.gl.setSwapInterval(.immediate);

    was_init = true;
}

pub fn deinit() void {
    if (!was_init)
        return;

    sdl.gl.deleteContext(glctx);
    _ = window.destroy();
    sdl.quit();
}

fn sdlLoadGlProcedure(ctx: void, name: [:0]const u8) ?*anyopaque {
    _ = ctx;
    return sdl.c.SDL_GL_GetProcAddress(name);
}

test {
    defer deinit();

    // _ = @import("raster.zig");
}
