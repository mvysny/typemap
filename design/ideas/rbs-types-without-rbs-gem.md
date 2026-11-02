# `RBSTypes` without the `rbs` gem

`RBSTypes` costs every app that uses it a runtime `rbs` dependency, and the boot time to load it.
Measured in pikuri-web (Ruby 3.3, rbs 4.2.0, three runs):

| step | time |
|---|---|
| `require "rbs"` | 148–161 ms |
| `RBS::Parser.parse_signature` of its 3 183-line `sig/pikuri_web.rbs` | 5–6 ms |

So nearly all of it is loading the gem, not parsing (`R_rbs_parser` has tuile's 870 KB file at
58 ms); and both pikuri shells pay it on every boot, to read a dozen config classes. The
dependency itself is lighter than it looks — Ruby 3.3 bundles rbs 3.4 — but whether its
`parse_signature` matches 4.2's is still `R_rbs_parser`'s one unverified line. Typemap already owns a parser for RBS *type* strings
(`TypeParser`, for `constrain type:`). What `RBSTypes` reads from a sig file is narrow:

- `module` / `class X < Y` nesting, for the fully qualified class name;
- `attr_reader` / `attr_accessor name: T`;
- `def name: () -> T`, a zero-argument method's return type.

Everything else in the file — method signatures with arguments, interfaces, type aliases,
comments, `%a{}` annotations — is skipped.

## The sketch

A small reader of its own: tokenize the sig file just enough to track `class` / `module` /
`interface` / `end` nesting and pick out the two member forms above, handing `T` to
`TypeParser`. `RBSTypes.new` then needs no `require "rbs"`; perhaps `RBSTypes.new(parser: :rbs)`
keeps the gem as an option for files the small reader can't handle.

## What makes it risky

- **RBS syntax is bigger than it looks.** A sord-written file holds procs (`^(String) -> void`),
  records (`{ a: Integer }`), tuples, `self`, `instance`, generics with bounds, and multi-line
  method types with overloads (`| (…) -> T`). The reader must at least *skip* each correctly to
  keep its nesting right; a skipped `end` inside a heredoc-like annotation would misfile every
  class after it. Needs a corpus: the sig files of pikuri-tui, pikuri-web and pikuri itself.
- **Two parsers drift.** `TypeParser` must then accept every type form sord writes for a
  property; today what it can't parse raises "unsupported type" (fine), but what it parses
  *differently* from rbs would be silent.
- **A second strategy to test.** Either the gem path goes (one less option for apps) or both
  are kept and tested.

## Open questions

- `Q_worth_it` — 150 ms on boot: does any consumer feel it? A TUI that starts many times a day
  does, a long-running server doesn't. Measure pikuri-tui's whole boot first; if it is 2 s,
  150 ms is noise.
- `Q_lazy_require` — cheaper middle ground: is it the `require` itself, or `rbs`'s eager loading
  of its whole AST and environment? `require "rbs/parser"`-only (if the gem allows it; the C
  extension may need more) might be most of the win with none of the risk.
- `Q_cache` — or precompile: `rake sig` (or a Typemap task) writes the property types as a
  tiny Ruby or JSON file beside `sig/`, and `RBSTypes` reads that. No parser at runtime at all;
  the cost is one more generated file to keep fresh.
