# `swift-format` Ignore/Disable Options

`swift-format` allows users to suppress formatting within a section of source
code. At present, this is only supported on declarations and statements due to
technical limitations of the formatter's implementation. When an ignore comment
is present, the next ["node"](#understanding-nodes) in the source's AST
representation is ignored by the formatter.

## Ignore A File

In the event that an entire file cannot be formatted, add a comment that contains
`swift-format-ignore-file` at the top of the file and the formatter will leave
the file completely unchanged.

```swift
// swift-format-ignore-file
import Zoo
import Arrays

struct Foo {
  func foo() { bar();baz(); }
}
```

## Ignoring Formatting (aka indentation, line breaks, line length, etc.)

The formatter applies line length to add line breaks and indentation throughout
source code. When this formatting isn't desired, it can be disabled by prefixing
a declaration or statement with a comment that contains "swift-format-ignore".

```swift
// swift-format-ignore
struct Foo {
	   var bar = true
}

// swift-format-ignore
func foo() {
	    var bar = true
}

// swift-format-ignore
var a = foo+bar+baz
```

Formatting is ignored for all children of the node where the ignore comment is
placed. For example, an ignore comment before a function causes the formatter to
ignore the entire code block of the function and an ignore comment before a
struct or class causes the formatter to ignore all of its members.

## Ignoring Source Transforming Rules

In addition to line breaks and indentation, the formatter provides a number of
rules that apply various source transformations to fix-up common issues in
source code. These rules can be disabled with a similar comment for disabling
formatting. All rules are disabled whenever a "swift-format-ignore" (with no
rule names) comment is encountered. When you want to disable a specific rule or
set of rules, add a comment of the form:

`// swift-format-ignore: [comma delimited list of rule names]`.

```swift
// swift-format-ignore: DoNotUseSemicolons
struct Foo {
	   var bar = true
}

// swift-format-ignore: DoNotUseSemicolons, FullyIndirectEnum, UseEarlyExits
func foo() {
	    var bar = true
}

// swift-format-ignore
var a = foo+bar+baz
```

These ignore comments also apply to all children of the node, identical to the
behavior of the formatting ignore directive described above.

You can also disable specific source transforming rules for an entire file
by using the file-level ignore directive with a list of rule names. For example:

```swift
// swift-format-ignore-file: DoNotUseSemicolons, FullyIndirectEnum
import Zoo
import Arrays

struct Foo {
  func foo() { bar();baz(); }
}
```
In this case, only the DoNotUseSemicolons and FullyIndirectEnum rules are disabled
throughout the file, while all other formatting rules (such as line breaking and
indentation) remain active.

## Disabling Rules Over a Region

The node-scoped `swift-format-ignore` directive covers the node that follows it.
For runs of code — tables of aligned data, generated code, a block of statements —
the block directives disable rules from one comment to another:

```swift
// swift-format-disable
let  aligned   =  table
var  values    =  here
// swift-format-enable
```

Between the two comments, every rule is disabled **and each covered statement
is printed verbatim**: the formatter does not change the spacing, line breaks,
or indentation within it. Two caveats: whitespace between the end of one
statement and the next is still normalized, and rules that decide on a whole
statement list rather than individual statements — such as `DoNotUseSemicolons`
and `OneVariableDeclarationPerLine` — consult the disable state where the list
begins, so a block opened inside a list does not suppress them for statements
above it. Use the named form to disable only specific rules, in which case the
region is still formatted normally and only the named rules are suppressed:

```swift
// swift-format-disable: DoNotUseSemicolons
func foo() { bar();baz(); }
// swift-format-enable
```

A `swift-format-disable` without a matching `swift-format-enable` runs to the end
of the file. Inside an all-rules block, `swift-format-enable: SomeRule`
re-enables just that rule. Directives are recognized before declarations and
statements (see [Understanding Nodes](#understanding-nodes) below) — including as
trailing comments on the previous line, like `swift-format-ignore`, in which case
the block's line-anchored range covers the directive's own line — and
additionally on the line before a closing `}`, so a block opened inside a
declaration can be closed at its end. Directives are honored wherever they are
recognized, including inside another disable block: an `enable` nested in one
closes it from that point on.

## Disabling Rules on a Single Line

Line-scoped directives suppress rules (and their lint findings) on one line
without touching anything else. They may trail code on the same line:

```swift
let a = 1  // swift-format-disable:this
let b = foo+bar+baz  // swift-format-disable:previous
// swift-format-disable:next DoNotUseSemicolons
func foo() { bar();baz() }
```

:this` covers the directive's own line, `:previous` the line before it, and
`:next` the line after it; each optionally followed by a list of rule names, or
no list to affect all rules. Line-scoped directives do **not** make text
verbatim — the pretty printer still normalizes spacing and line breaks on the
covered line. Like block directives, they mask rules whose decision point is
the enclosing statement list at the list's first line, so a line scope above a
multi-statement list affects that list as a whole. Use a node-level `swift-format-ignore` or a
`swift-format-disable` block when the text must be preserved exactly.

## Understanding Nodes

`swift-format` parses Swift into an abstract syntax tree, where each element of
the source is represented by a node. Formatting can only be suppressed on
certain "top level nodes" due to limitations of the syntax visitor pattern used
by the formatter. Limiting to these nodes ensures there will be no mismatched
formatting instructions (i.e. start a group without a corresponding end). The
top level nodes that support suppressing formatting are:

- `CodeBlockItemSyntax`, which is either:
  - A single expression (e.g. function call, assignment, expression)
  - A scoped block of code & associated statement(s) (e.g. function declaration,
    struct/class/enum declaration, if/guard statements, switch statement, while
    loop). All code nested syntactically inside of the ignored node is also
    ignored by the formatter. This means ignoring a struct declaration also
    ignores all code inside of the struct declaration.
- `MemberBlockItemSyntax`
  - Any member declaration inside of a declaration (e.g. properties and
    functions declared inside of a struct/class/enum). All code nested
    syntactically inside of the ignored node is also ignored by the formatter.

## File-Based Ignoring with `.swift-format-ignore`

In addition to the comment-based ignoring described above, `swift-format` supports
file-based ignoring using `.swift-format-ignore` files. These files allow you to
specify patterns for files and directories that should be completely excluded from
formatting and linting operations.

### `.swift-format-ignore` File Format

`.swift-format-ignore` files use the same pattern syntax as `.gitignore` files:

```
# This is a comment
*.generated.swift
build/
**/Generated/
!important.swift
src/**/test*.swift
```

### Pattern Syntax

The `.swift-format-ignore` files supports the following pattern syntax:

- Simple patterns: `file.swift` matches any file named `file.swift` anywhere in the tree
- Wildcard patterns: `*.swift` matches all files ending with `.swift`
- Directory patterns: `build/` matches the `build` directory and all files within it
- Nested wildcards: `**/*.generated` matches files with `.generated` extension at any depth
- Negation patterns: `!important.swift` excludes `important.swift` from being ignored (even if matched by other patterns)
- Absolute patterns: `/root.swift` matches `root.swift` only at the project root
- Complex patterns: `src/**/test*.swift` matches files starting with `test` and ending with `.swift` anywhere under `src/`

### File Discovery and Precedence

`swift-format` searches for `.swift-format-ignore` files by walking up the directory
tree from each source file being processed. Multiple ignore files can exist in a
project, with the following precedence rules:

1. Closest wins: Ignore files closer to the source file take precedence
2. Directory traversal: The tool searches from the file's directory up to the discovery of a `.swift-format` file
3. Pattern evaluation: Within each ignore file, patterns are evaluated in order
4. Negation support: Later negation patterns (`!pattern`) can override earlier ignore patterns

### Example Project Structure

```
project/
├── .swift-format-ignore          # Root ignore file
├── src/
│   ├── .swift-format-ignore      # Overrides root for src/ directory
│   ├── main.swift
│   └── generated/
│       └── Generated.swift
├── tests/
│   └── test.swift
└── build/
    └── output.swift
```

**Root `.swift-format-ignore`:**
```
# Ignore all generated files
*.generated.swift
build/
```

**`src/.swift-format-ignore`:**
```
# Additional rules for src directory
generated/
!important.generated.swift
```

### Integration with swift-format Commands

The `.swift-format-ignore` functionality works automatically with all `swift-format` commands:

```bash
# Format all files except those matching ignore patterns
swift-format --recursive src/

# Lint all files except those matching ignore patterns
swift-format lint --recursive src/

# Both commands will automatically discover and respect .swift-format-ignore files
```

Files matched by `.swift-format-ignore` patterns are completely excluded from processing -
they will not be formatted, linted, or appear in any output.
