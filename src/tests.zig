//! Behavioral tests use the same exported modules as embedders.
test {
    _ = @import("tests/eu.zig");
    _ = @import("tests/raw/engine.zig");
    _ = @import("tests/raw/simdutf.zig");
    _ = @import("tests/raw/contexts.zig");
    _ = @import("tests/raw/primitives.zig");
    _ = @import("tests/raw/arrays.zig");
    _ = @import("tests/raw/objects.zig");
    _ = @import("tests/raw/functions.zig");
    _ = @import("tests/raw/return_values.zig");
    _ = @import("tests/raw/property_callbacks.zig");
    _ = @import("tests/raw/templates.zig");
    _ = @import("tests/raw/persistent_handles.zig");
    _ = @import("tests/raw/promises.zig");
    _ = @import("tests/raw/fixed_arrays.zig");
    _ = @import("tests/raw/scripts.zig");
    _ = @import("tests/raw/termination.zig");
    _ = @import("tests/raw/host_callbacks.zig");
    _ = @import("tests/raw/values.zig");
}
