# Prude - Odin Prelude Generator

A simple [Odin](https://odin-lang.org) tool for "lifting" declarations from inner packages into an upper package by way of a "prelude" file. I guess this can technically thought of as a header file generator for odin libraries.

## Quickstart

```
git clone https://github.com/eu-lo/prude.git
odin run prude -- path/to/lib 
```

## Rationale 

This tool originally began as an internal package inside another project of mine. I wanted to seperate my code into a "lib" folder, as is standard for most projects. Typically, doing this would require users of my library to manually path to said folder in order to use it, and it would prevent Odin from automagically determining the name of the import for them. I feel like such an approach is also an anti-pattern, because it forces users to work around the internal project structure rather than letting the code describe itself. But, I wanted it anyway, and I've seen a few other Odin repos make this change too, despite the issues. 

One solution to this would be to write a file in project root that re-exports symbols from the inner "lib" or "src" package so that users can still clone-and-use without issue. The main issue is that this adds considerable friction to re-factoring; it essentially re-invents the concept of header files in odin. This is where Prude is designed to help: It parses a set of odin files within a folder or list of folders (i.e. a list of odin packages) and produces an odin file which re-exports every publically accessable declaration.

I do understand that this is sort of against the design of Odin, as it encourages "compartmentalization" and "code taxonomy" in ways that Odin is specifically designed to discourage. This tool isn't necessarily meant to circumvent this, and is only meant to make libraries more ergonomic to use and develop. Think of it more like a build tool than a distriution strategy.

This project isn't for everyone! Remember that users of your library can still just manually import anything within the project--all Prude does is "lift" items to the "top-level". If your project is not intended to be used as a odin-native library or has some other build system that is not as simple as "clone into your project and import", then this project may not be for you. But in the end it's just a simple tool built with the core library's parser package that I found useful. I hope it proves useful to you too.

## Installation

You can build the project with `odin build .` (maybe with an `-o:speed` tacked on the end if you want). The `Justfile` is not needed for end users, and can be ignored if you don't change any of the code. (See [Development](#development) for a brief summary on what its for.)

If you want to use this project as a library (perhaps in your build script, if you have one), or if you'd rather run it using `odin run`, clone it to your project directory and import it normally:
```
git clone https://github.com/eu-lo/prude.git
odin run prude -- ...
```

Or you can use git subtrees:
```
git subtree add https://github.com/eu-lo/prude -P prude --squash
odin run prude -- ...
```

## Usage

Prude can be used either as a CLI tool or as a library. Should you have any issues feel free to open a ticket here!

### As a CLI Tool:
```
prude lib include          # Scans ./lib/ and ./include/, outputs to prelude.odin
odin run prude -- lib      # If cloned to your project
prude lib lib/core         # Prude does not scan sub-directories
prude lib -docs:README.md  # Add file contents to package documentation
prude src -target:lib.odin # Change target destination
prude core -whitelist      # Run in whitelist mode
```

Running `prude -help` prints:
```
Usage:
        prude.exe [-debug] [-docs] [-name] [-quiet] [-target] ...
Flags:
        -debug            | Enable debug log output.
        -docs:<^File>     | File to embed into the documentation of the 'package' declaration.
        -name:<string>    | Name of the package. Defaults to directory name.
        -quiet            | Disable default log output. Setting this implicitly disables '-debug' as well.
        -whitelist        | Treat entries as whitelist rather than blacklist.
        -target:<string>  | Output prelude file. Defaults to 'prelude.odin'.
        <string, ...>     | Directories to include in the prelude. Does not scan subdirectories.
```

### As a library:
```go
import "prude"
main :: proc() {
    p : prude.Prelude
    // ZII--this is ready to go
    prude.add_source(&p, "path/to/package")

    // Set these before writing prelude
    p.name = "my_package"
    p.path = "lib.odin"

    prude.output_to_file(&p)
    result := prude.output_to_string(&p) // Can also write to string
    // All of these return errors if any occured
}
```

## Features

* Simple prelude file generation:
    ```go
    package lib
    Item :: struct { ... }
    procedure :: proc() { ... }
    constant :: 10

    Conflicting_Item :: struct { ... }

    package net
    Other_Item :: struct { ... }
    Error :: enum { ... }
    Conflicting_Item :: enum { ... }

    // "prelude.odin"
    package name
    import "lib"
    import "net"

    Item :: lib.Item
    procedure :: lib.procedure
    constant :: lib.constant
    Conflicting_Item :: lib.Conflicting_Item
    Other_Item :: net.Other_Item
    Error :: net.Error
    net_Conflicting_Item :: net.Conflicting_Item
    ```

    It is recommended to rename or exclude entries which result in naming conflicts (see below). 

* Individual item renaming:
    ```go
    package net

    Other_Item :: struct { ... }
    @(tag = "prelude:Net_Error")
    Error :: enum { ... }

    // "prelude.odin"
    package name
    import "net"

    Other_Item :: net.Other_Item
    Net_Error :: net.Error
    ```


* Blacklist mode (on by default):
    ```go
    package net

    Other_Item :: struct { ... }
    @(tag = "prelude:_")
    Error :: enum { ... }

    // "prelude.odin"
    package name
    import "net"

    Other_Item :: net.Other_Item
    ```

* Whitelist mode:
    ```go
    package net

    @(tag = "prelude")
    Other_Item :: struct { ... }
    Error :: enum { ... }

    // "prelude.odin"
    package name
    import "net"

    Other_Item :: net.Other_Item
    ```

    To use whitelist mode, run `prude` with `-whitelist`. If using the library, set `is_whitelist` on the `Prelude` object before adding sources.
    `when` statements and files with file suffixes automatically use whitelist mode (See [Caveats](#caveats)).

* Documentation embedding:
    ```
    prude lib -docs:README.md
    ```

    ```go
    // "prelude.odin"

    // # Prude - Odin Prelude Generator
    // 
    // A simple Odin tool...
    package name
    ```

    This is useful if you have an existing document that you'd like to embed into your top-level package documentation. If you write that manually, you're better off including that in a `docs.odin` file or something.

### Caveats

Prude *will* parse `when` statements and any declarations within them, but will force `whitelist` mode when doing so. Prude does **not** do any analysis of your code and so there isn't a safe way to properly import declarations within when statements. Typically, you should write a seperate file adjacent to the prelude yourself and manually maintain the compile-time conditions, but if you are sure it's safe to import a certain item you can add `@(tag = "prelude")` above it to force-import the item. If the same item is imported multiple times, Prude will not import it more than once.

The above also applies to any files with [file suffixes](https://odin-lang.org/docs/overview/#file-suffixes).

Here's an example of how this might work:

```go
package lib

// Different per architecture, but the procedure exists no matter what, so it's safe to let prude handle it.
when ODIN_OS == .Windows {
    @(tag = "prelude")
    arch_specific_proc :: proc (...) { ... }
} else {
    @(tag = "prelude") // Technically this tag is unnecessary
    arch_specific_proc :: proc (...) { ... }
}

// This is only conditionally computed. Because you can use more complex conditions (with custom defines and whatnot), prude ignores this by default.
when ODIN_DEBUG {
    Debug_Only_Struct :: struct { ... }
}

// "prelude.odin"
import "lib"

arch_specific_proc :: lib.arch_specific_proc

// In a seperate, handwritten file, perhaps called "prelude_footer.odin"
import "lib"

// This ensures release builds aren't broken by prude
when ODIN_DEBUG {
    Debug_Only_Struct :: lib.Debug_Only_Struct
}
```

Additionally, all import paths in the resulting odin file are made relative to the file, so moving folders around requires a regeneration of the prelude file.

## Development

If you want to hack away on this, be my guest! Aside from the Odin toolchain, you also need [Just](https://just.systems). To see what you can do, run `just`. Each recipe contains a small description of what it does. To run a debug build, use `just run-debug` (or `just rd`), and to test, use `just test`. To run linters, use `just check`, and to generate the prelude file (should be done before every commit but its an easy Amend or extra commit to fix it), use `just make-prelude`.

## License

[Unlicense](https://choosealicense.com/licenses/unlicense/)
