package core

import "base:runtime"
import "core:os"

// Errors than can occur during scanning and generation.
Error :: union {
	os.Error,
	runtime.Allocator_Error,
	Scan_Error,
}

// An error that occured during the scanning phase.
Scan_Error :: enum {
	None,
	// Attempted to scan a non-odin file. This only occurs when manually adding paths via `prelude_add_file`.
	Non_Odin_File,
	// Attempted to scan a path that did not lead to a file.
	Not_A_File,
	// Odin could not successfully finishing parsing. Run `odin check` on it and see what's wrong.
	Invalid_Odin_Code,
	// Attempted to add source with path that was not a directory.
	// Prude only works with entire packages, not individual files.
	Not_A_Directory,
}

// A collection of entries and sources associated with a package name. Used to generate a source code file.
// Be sure to initialize with `prelude_init` (or allocate with `prelude_make`) and free with `prelude_destroy`.
// Before using, set `name` and `path`.
Prelude :: struct {
	entries :      [dynamic]Entry,
	sources :      [dynamic]Source,
	// An optional string with documentation that goes before the 'package' declaration.
	docs :         string,
	// The name of the package. Should be set before adding any sources.
	name :         string,
	// The path of the resulting prelude file. Should be a file, not a directory, and have write permissions.
	path :         string,
	// Whether entries are whitelisted or blacklisted.
	is_whitelist : bool,
}

// An exported entry to be placed in the prelude.
Entry :: struct {
	// The exported name of the object.
	name :          string,
	// The source of the object, typically in the form of `package_name.ObjectName`.
	source :        string,
	// The documentation comments preceding the object definition.
	documentation : string,
}

// A description of a path to a package and its name as referenced in code.
Source :: struct {
	// The name of the package. Typically matches the last element of `path`, but in the case of naming conflicts may be slightly obfuscated.
	name : string,
	// The path to the package as relative to the prelude file.
	path : string,
}
