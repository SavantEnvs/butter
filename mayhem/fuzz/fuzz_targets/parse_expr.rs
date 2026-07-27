#![no_main]
//! Fuzz the expression parser: feed an arbitrary source string to
//! `parser::expr_parser()` (butter's single-expression parser, as used by the
//! type-inference REPL). Exercises operator/precedence, string, number, array,
//! record and tuple sub-parsers.
use libfuzzer_sys::fuzz_target;
use parser::{EasyParser, expr_parser};

fuzz_target!(|src: &str| {
    let _ = expr_parser().easy_parse(src);
});
