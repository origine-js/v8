const binding = @import("../binding.zig");
const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Data = v8.Data;
const Value = v8.Value;

pub const ScriptOrigin = struct {
    pub const Opaque = [binding.sizes.ScriptOrigin]u8;

    const Self = @This();

    inner: Opaque align(@alignOf(usize)),

    pub fn initDefault(resource_name: Value) Self {
        return init(
            resource_name,
            0,
            0,
            false,
            -1,
            null,
            false,
            false,
            false,
            null,
        );
    }

    pub fn init(
        resource_name: Value,
        resource_line_offset: c_int,
        resource_column_offset: c_int,
        resource_is_shared_cross_origin: bool,
        script_id: c_int,
        source_map_url: ?Value,
        resource_is_opaque: bool,
        is_wasm: bool,
        is_module: bool,
        host_defined_options: ?Data,
    ) Self {
        var place: ScriptOrigin = undefined;
        e.v8__ScriptOrigin__CONSTRUCT(
            &place.inner,
            resource_name,
            resource_line_offset,
            resource_column_offset,
            resource_is_shared_cross_origin,
            script_id,
            if (source_map_url) |v| v.data.handle else null,
            resource_is_opaque,
            is_wasm,
            is_module,
            if (host_defined_options) |v| v.handle else null,
        );
        return place;
    }

    pub fn scriptId(self: *const v8.ScriptOrigin) c_int {
        return e.v8__ScriptOrigin__ScriptId(&self.inner);
    }

    pub fn resourceName(self: *const v8.ScriptOrigin) ?v8.Value {
        return v8.Value.from_opaque(e.v8__ScriptOrigin__ResourceName(&self.inner));
    }

    pub fn sourceMapUrl(self: *const v8.ScriptOrigin) ?v8.Value {
        return v8.Value.from_opaque(e.v8__ScriptOrigin__SourceMapUrl(&self.inner));
    }
};
