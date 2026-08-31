# Output guarantees

These output guarantees hold for every configuration.
They are pinned by `OutputGuaranteesTests`, `ByteOrderMarkerTests`, and the
CLI-level BOM tests in `FormatFrontendCheckTests`. Together they pin the output guarantees:
for a given configuration, the output depends only on the syntax, the author-placed blank
lines between statements, the magic trailing comma, and the line length.

## Line endings

- Output uses **LF (`\n`) exclusively** everywhere outside string literal content. A CRLF (or
  lone CR) input is normalized to LF on rewrite.
- A carriage return that is *content* of a string literal is source data and is preserved.

## End of file

- Non-empty output ends with **exactly one trailing newline**. A missing final newline is
  restored; a trailing run of blank lines collapses to that single newline.
- An empty input produces empty output (the formatting driver skips empty sources entirely).
- Blank lines *between* statements are not "trailing" whitespace: they are author-placed
  blank lines: preserved (clamped by `maximumBlankLines`) by default, and governed by
  `BlankLinePolicy` when that rule is enabled.

## Byte order mark

- The formatter proper **preserves a leading UTF-8 BOM** in its output.
- The command line tool's file-rewrite path (`--in-place`, and the formatted bytes it writes
  back) **drops a leading BOM**, because the UTF-8 file reader treats it as an encoding
  signature and strips it on read. Files rewritten by the command line tool therefore
  contain no BOM.

## Unicode normalization

- The formatter performs **no Unicode normalization**. Identifiers, comments, and string
  literal content pass through byte-identically: NFC and NFD spellings of the same text are
  different bytes in, different bytes out (and, for identifiers, different identifiers to the
  compiler). A project that wants a single normalization form must establish it upstream of the
  formatter; the opt-in `IdentifiersMustBeASCII` lint rule separately rejects non-ASCII
  identifiers without rewriting them.
