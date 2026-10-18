const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const JSON = extern struct {
    pub fn parse(context: v8.Context, json_string: v8.String) ?v8.Value {
        return v8.Value.from_opaque(e.v8__JSON__Parse(context, json_string));
    }

    pub fn stringify(context: v8.Context, json_object: v8.Value) ?v8.String {
        return v8.String.from_opaque(e.v8__JSON__Stringify(context, json_object));
    }
};
