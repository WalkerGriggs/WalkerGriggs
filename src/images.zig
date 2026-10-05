//! Raster images → resized WebP, via ImageMagick's `convert`.
const std = @import("std");

/// 2× the widest Tufte text column (~675 CSS px), so images stay sharp on high-DPI screens.
const max_width = "1350x>";

pub const Image = struct { src: []const u8, w: []const u8, h: []const u8 };

pub fn isRaster(path: []const u8) bool {
    const ext = std.fs.path.extension(path);
    for ([_][]const u8{ ".png", ".jpg", ".jpeg", ".gif", ".webp" }) |e| if (std.ascii.eqlIgnoreCase(ext, e)) return true;
    return false;
}

/// Converts `src` to a WebP at `dst` (paths relative to the working directory) and returns its size.
pub fn toWebp(arena: std.mem.Allocator, io: std.Io, src: []const u8, dst: []const u8) !struct { []const u8, []const u8 } {
    const argv = [_][]const u8{ "convert", try std.fmt.allocPrint(arena, "{s}[0]", .{src}), "-auto-orient", "-resize", max_width, "-strip", "-quality", "80", "-define", "webp:method=6", "-print", "%w %h", dst };
    const res = std.process.run(arena, io, .{ .argv = &argv }) catch |err| {
        std.log.err("could not run ImageMagick `convert` ({t}); is it installed?", .{err});
        return err;
    };
    if (res.term != .exited or res.term.exited != 0) {
        std.log.err("converting {s} failed: {s}", .{ src, res.stderr });
        return error.ImageConversionFailed;
    }
    const space = std.mem.indexOfScalar(u8, res.stdout, ' ') orelse return error.ImageConversionFailed;
    return .{ res.stdout[0..space], std.mem.trim(u8, res.stdout[space + 1 ..], " \n") };
}
