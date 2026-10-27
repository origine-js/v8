// The ICU data package embedded as-is. ICU_DATA_PATH (a string literal) is passed by
// build/icu.build.zig; ICU requires its common data to be 16-byte aligned.
#if defined(__APPLE__)
#define SYM(name) _##name
    .section __DATA_CONST,__const
#else
#define SYM(name) name
    .section .rodata,"a",@progbits
#endif
    .globl SYM(v8_zig_icu_raw)
    .balign 16
SYM(v8_zig_icu_raw):
    .incbin ICU_DATA_PATH
