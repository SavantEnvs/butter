#![no_main]
//! Fuzz butter's ORIGINAL `parser-repl` REPL loop (`cli/src/main.rs`'s `parser_repl()`), converted
//! from a raw-stdin CLI (the mayhemheroes `butter-parser-repl` target) to an in-process libFuzzer
//! harness over the SAME code path. Each REPL iteration calls `stdin.read_line(&mut input)?`;
//! `BufRead::read_line` returns an `InvalidData` error ("stream did not contain valid UTF-8") if
//! the bytes aren't valid UTF-8, and `parser_repl()`'s `?` propagates that up to `main()`'s
//! `.unwrap()` -- an uncaught panic (CWE-617, mayhemheroes run 6). We feed raw bytes through a
//! `Cursor` into the same `BufRead::read_line` call the REPL makes, then, on success, hand the
//! line to `parser::expr_parser()` exactly like the REPL does.
use libfuzzer_sys::fuzz_target;
use parser::{EasyParser, expr_parser};
use std::io::BufRead;

fuzz_target!(|data: &[u8]| {
    let mut input = String::new();
    let mut cursor = std::io::Cursor::new(data);
    cursor.read_line(&mut input).unwrap();
    let _ = expr_parser().easy_parse(&input[..]);
});
