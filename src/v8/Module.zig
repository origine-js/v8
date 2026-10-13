const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Data = v8.Data;

pub const Module = extern struct {
    data: Data,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .data = v8.Data.from_opaque(o) orelse return null };
    }

    pub fn getStatus(self: v8.Module) u32 {
        return e.v8__Module__GetStatus(self);
    }

    pub fn getException(self: v8.Module) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Module__GetException(self));
    }

    pub fn getModuleRequests(self: v8.Module) ?v8.FixedArray {
        return v8.FixedArray.from_opaque(e.v8__Module__GetModuleRequests(self));
    }

    pub fn sourceOffsetToLocation(self: v8.Module, offset: c_int, out: ?*v8.Location) void {
        e.v8__Module__SourceOffsetToLocation(self, offset, out);
    }

    pub fn getModuleNamespace(self: v8.Module) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Module__GetModuleNamespace(self));
    }

    pub fn getIdentityHash(self: v8.Module) c_int {
        return e.v8__Module__GetIdentityHash(self);
    }

    pub fn scriptId(self: v8.Module) c_int {
        return e.v8__Module__ScriptId(self);
    }

    pub fn instantiateModule(self: v8.Module, context: v8.Context, cb: @typeInfo(v8.Callbacks.Module_ResolveModuleCallback).optional.child, source_callback: v8.Callbacks.Module_ResolveSourceCallback) ?bool {
        return e.v8__Module__InstantiateModule(self, context, cb, source_callback).as_optional();
    }

    pub fn evaluate(self: v8.Module, context: v8.Context) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Module__Evaluate(self, context));
    }

    pub fn isGraphAsync(self: v8.Module) bool {
        return e.v8__Module__IsGraphAsync(self);
    }

    pub fn isSourceTextModule(self: v8.Module) bool {
        return e.v8__Module__IsSourceTextModule(self);
    }

    pub fn isSyntheticModule(self: v8.Module) bool {
        return e.v8__Module__IsSyntheticModule(self);
    }

    pub fn createSyntheticModule(isolate: v8.Isolate, module_name: ?v8.String, export_names_len: usize, export_names_raw: @typeInfo(@TypeOf(e.v8__Module__CreateSyntheticModule)).@"fn".param_types[3].?, evaluation_steps: v8.Callbacks.Module_SyntheticModuleEvaluationSteps) ?v8.Module {
        return v8.Module.from_opaque(e.v8__Module__CreateSyntheticModule(isolate.handle, if (module_name) |v| v8.support.rawHandle(v) else null, export_names_len, export_names_raw, evaluation_steps));
    }

    pub fn setSyntheticModuleExport(self: v8.Module, isolate: v8.Isolate, export_name: ?v8.String, export_value: ?v8.Value) ?bool {
        return e.v8__Module__SetSyntheticModuleExport(self, isolate.handle, if (export_name) |v| v8.support.rawHandle(v) else null, if (export_value) |v| v8.support.rawHandle(v) else null).as_optional();
    }

    pub fn getUnboundModuleScript(self: v8.Module) ?v8.UnboundModuleScript {
        return v8.UnboundModuleScript.from_opaque(e.v8__Module__GetUnboundModuleScript(self));
    }

    pub fn getStalledTopLevelAwaitMessage(self: v8.Module, isolate: v8.Isolate, out: []v8.StalledTopLevelAwaitMessage) usize {
        return e.v8__Module__GetStalledTopLevelAwaitMessage(self, isolate.handle, @ptrCast(out.ptr), out.len);
    }
};
