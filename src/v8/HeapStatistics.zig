const v8 = @import("../v8.zig");

pub const HeapStatistics = extern struct {
    total_heap_size: usize,
    total_heap_size_executable: usize,
    total_physical_size: usize,
    total_available_size: usize,
    used_heap_size: usize,
    heap_size_limit: usize,
    malloced_memory: usize,
    external_memory: usize,
    peak_malloced_memory: usize,
    does_zap_garbage: bool,
    number_of_native_contexts: usize,
    number_of_detached_contexts: usize,
    total_global_handles_size: usize,
    used_global_handles_size: usize,
    total_allocated_bytes: u64,
};
