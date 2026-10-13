const e = @import("../externs.gen.zig");

pub const ResourceConstraints = extern struct {
    code_range_size_: usize,
    max_old_generation_size_: usize,
    max_young_generation_size_: usize,
    initial_old_generation_size_: usize,
    initial_young_generation_size_: usize,
    physical_memory_size_: u64,
    stack_limit_: *const u32,

    pub fn configureDefaultsFromHeapSize(self: *ResourceConstraints, initial_heap_size_in_bytes: usize, maximum_heap_size_in_bytes: usize) void {
        e.v8__ResourceConstraints__ConfigureDefaultsFromHeapSize(self, initial_heap_size_in_bytes, maximum_heap_size_in_bytes);
    }

    pub fn configureDefaults(self: *ResourceConstraints, physical_memory: u64, virtual_memory_limit: u64) void {
        e.v8__ResourceConstraints__ConfigureDefaults(self, physical_memory, virtual_memory_limit);
    }
};
