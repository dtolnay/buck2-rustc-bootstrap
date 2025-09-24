// Allocations in Rust code invoke `__rust_alloc` and its kin under the hood.
// These functions aren't actually implemented anywhere - instead, the compiler
// will in certain cases inject an "allocator shim" implementation for them
// which calls the corresponding *actual* implementation:
// - `__rdl_*` by default
// - `__rg_*` if `#[global_allocator]` is set
//
// The cases in which an allocator shim is generated are:
// - when building a `bin` crate
// - when building a `staticlib` crate
// - when building a `cdylib` crate
// - when building *the first* `dylib` crate in a dependency graph
//
// There are use cases where none of those criteria are satisfied yet we still
// need an allocator. For example, in a diamond dependency scenario:
//
//                              foo.cpp  <- top-level target
//                              /    \
//                             /      \
//                         left.rs   right.rs
//                             \      /
//                              \    /
//                             shared.rs
//
// Officially `left.rs` and `right.rs` are supposed to be built as `staticlib`
// or `cdylib` crates which both bundle `shared.rs` and the standard library in
// their output. This has several downsides (bloat, symbol collisions, singleton
// conflicts...) so we want to build them as `rlib` crates instead. If all of
// our Rust crates are `rlib`s, we won't get an allocator shim.
//
// We can't get the compiler to generate an allocator shim for us, but we can
// effectively provide our own by defining `__rust_alloc` and friends ourselves
// to point to the default allocator.
//
// In case it comes up, on Android we have to use a custom malloc because
// Clang+LLVM assume allocations are 16-byte-aligned which is not guaranteed to
// be true on Android 6 and earlier. This can result in a SIGBUS.

#![feature(alloc_internals)]
#![feature(linkage)]
#![feature(rustc_attrs)]
#![cfg_attr(not(feature = "std"), no_std)]

#[cfg(feature = "std")]
pub mod std_alloc;

extern crate alloc;

use alloc::alloc::__alloc_error_handler;

#[rustc_std_internal_symbol]
#[linkage = "weak"]
pub unsafe fn __rust_alloc_error_handler_should_panic_v2() -> u8 {
    1
}

#[rustc_std_internal_symbol]
#[linkage = "weak"]
pub unsafe fn __rust_no_alloc_shim_is_unstable_v2() {}

#[rustc_std_internal_symbol]
#[cfg_attr(not(target_os = "ios"), linkage = "weak")]
pub unsafe fn __rust_alloc_error_handler(size: usize, align: usize) -> ! {
    unsafe { __alloc_error_handler::__rdl_oom(size, align) }
}

#[rustc_std_internal_symbol]
#[linkage = "weak"]
pub unsafe fn __rg_oom(size: usize, align: usize) -> ! {
    unsafe { __alloc_error_handler::__rdl_oom(size, align) }
}
