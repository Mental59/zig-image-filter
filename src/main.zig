const std = @import("std");
const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("spng.h");
});

pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = std.heap.smp_allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const args = try init.args.toSlice(arena.allocator());
    if (args.len <= 1) {
        @panic("png file is not specified");
    }

    const png_path = args[1];

    const file_descriptor = c.fopen(png_path, "rb");
    if (file_descriptor == null) {
        @panic("Could not open png file!");
    }
    defer {
        if (c.fclose(file_descriptor) != 0) {
            @panic("Could not close png file");
        }
    }

    const ctx = c.spng_ctx_new(0);
    if (ctx == null) {
        @panic("Failed to create spng context");
    }
    defer c.spng_ctx_free(ctx);

    const set_png_res = c.spng_set_png_file(ctx, @ptrCast(file_descriptor));
    if (set_png_res != 0) {
        @panic("Failed to set png file");
    }

    const output_size = try calc_output_size(ctx.?);
    const buffer = try allocator.alloc(u8, output_size);

    try read_data_to_buffer(ctx.?, buffer);
    try apply_image_filter(buffer);
    var image_header = try get_image_header(ctx.?);
    try save_png(&image_header, buffer);
}

fn get_image_header(ctx: *c.spng_ctx) !c.spng_ihdr {
    var image_header: c.spng_ihdr = undefined;
    if (c.spng_get_ihdr(ctx, &image_header) != 0) {
        return error.CouldNotGetImageHeader;
    }
    return image_header;
}

fn calc_output_size(ctx: *c.spng_ctx) !usize {
    var output_size: usize = 0;
    const status = c.spng_decoded_image_size(
        ctx,
        c.SPNG_FMT_RGBA8,
        &output_size,
    );
    if (status != 0) {
        return error.CouldNotCalculateOutputSize;
    }
    return output_size;
}

fn read_data_to_buffer(ctx: *c.spng_ctx, buffer: []u8) !void {
    const status = c.spng_decode_image(
        ctx,
        buffer.ptr,
        buffer.len,
        c.SPNG_FMT_RGBA8,
        0,
    );

    if (status != 0) {
        return error.CouldNotDecodeImage;
    }
}

fn apply_image_filter(buffer: []u8) !void {
    const red_factor: f32 = 0.2126;
    const green_factor: f32 = 0.7152;
    const blue_factor: f32 = 0.0722;

    var index: usize = 0;
    while (index < buffer.len) : (index += 4) {
        const rf: f32 = @floatFromInt(buffer[index]);
        const gf: f32 = @floatFromInt(buffer[index + 1]);
        const bf: f32 = @floatFromInt(buffer[index + 2]);

        const y_linear: f32 = ((rf * red_factor) + (gf * green_factor) + (bf * blue_factor));

        buffer[index] = @intFromFloat(y_linear);
        buffer[index + 1] = @intFromFloat(y_linear);
        buffer[index + 2] = @intFromFloat(y_linear);
    }
}

fn save_png(image_header: *c.spng_ihdr, buffer: []u8) !void {
    var image_header_copy = image_header.*;
    image_header_copy.bit_depth = 8;
    image_header_copy.color_type = c.SPNG_COLOR_TYPE_TRUECOLOR_ALPHA;

    const path = "result.png";
    const file_descriptor = c.fopen(path.ptr, "wb");
    if (file_descriptor == null) {
        return error.CouldNotOpenFile;
    }
    defer {
        if (c.fclose(file_descriptor) != 0) {
            @panic("Could not close result file");
        }
    }
    const ctx = c.spng_ctx_new(c.SPNG_CTX_ENCODER);
    if (ctx == null) {
        return error.CouldNotCreateContext;
    }
    defer c.spng_ctx_free(ctx);

    if (c.spng_set_png_file(ctx, @ptrCast(file_descriptor)) != 0) {
        return error.CouldNotSetPngFile;
    }
    if (c.spng_set_ihdr(ctx, &image_header_copy) != 0) {
        return error.CouldNotSetImageHeader;
    }

    const encode_status = c.spng_encode_image(
        ctx,
        buffer.ptr,
        buffer.len,
        c.SPNG_FMT_PNG,
        c.SPNG_ENCODE_FINALIZE,
    );
    if (encode_status != 0) {
        const error_desc = c.spng_strerror(encode_status);
        std.log.err("Failed to encode image: {s}", .{error_desc});
        return error.CouldNotEncodeImage;
    }
}
