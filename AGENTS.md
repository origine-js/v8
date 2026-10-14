# Function ownership and lifetime documentation

Every function must have an adjacent comment or documentation comment specifying
its ownership and lifetime contract. This applies to public and private functions,
methods, callbacks, function-pointer fields, extern declarations, and test helpers.
Use `///` documentation comments for Zig declarations.

Document the following wherever applicable:

- **Inputs and receiver:** Identify borrowed, copied, retained, or consumed resources,
  including nested slices, strings, pointers, handles, and callback state. State how
  long borrowed storage must remain valid and whether it must remain immutable.
- **Results:** State who owns returned storage or handles, which allocator backs
  them, how and when to release them, and whether they alias an input or internal
  state. Give the exact validity boundary for borrowed results.
- **Allocators:** State whether the allocator and its state are borrowed or retained,
  how long they must live, and who releases allocations made through them.
- **Failure paths:** Explain ownership transfer and cleanup on both success and
  error, including partial initialization and resources retained after failure.
- **Execution requirements:** State required stable addresses, entered V8 contexts,
  live handle scopes, thread affinity, and asynchronous or teardown lifetimes.

Use concrete boundaries such as “until this call returns,” “until the next mutation,”
or “until `Runtime.deinit` begins.” Distinguish local V8 handles from caller-owned
persistent handles. Document ownership transfer separately from copying and mutation.

For functions with no resource ownership or lifetime requirements, say so explicitly
in a short comment, for example: “Accepts and returns values; retains no resources.”
Keep comments proportional to the contract; omit inapplicable categories.

When adding or changing a function, update its contract alongside the implementation.
Before completing a change, verify that every added or modified function has an
accurate ownership and lifetime comment, including its error paths and nested data.

# Naming convention

`allocate` -> `alloc`

Prefer these names for local variables and parameters of the corresponding types:

| Type | Recommended naming |
| --- | --- |
| `v8.TryCatch` | `tc_scope` |
| `v8.HandleScope` | `h_scope` |
| `std.mem.Allocator` | `alloc` |
| `v8.ArrayBuffer.Allocator` | `aba` |
