#![no_main]
//! Fuzz the whole-program parser: feed an arbitrary source string to
//! `parser::ast()` (butter's top-level statement-list parser). libfuzzer-sys
//! hands us a valid &str; combine's EasyParser turns it into an AST or an error.
use libfuzzer_sys::fuzz_target;
use parser::{EasyParser, ast};

fuzz_target!(|src: &str| {
    // Errors are expected (most random input is not valid butter). We fuzz for
    // panics / memory-safety defects in the parser, not for parse success.
    let _ = ast().easy_parse(src);
});
