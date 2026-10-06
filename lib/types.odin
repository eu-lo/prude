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
	// Tried to output prelude with an empty path.
	Path_Empty,
	// Attempted to scan a non-odin file. This only occurs when manually adding paths via `prelude_add_file`. Non-odin files read through `add_source` are skipped.
	Non_Odin_File,
	// Attempted to scan a path that did not lead to a file.
	Not_A_File,
	// Odin could not successfully finishing parsing. Run `odin check` on the package and see what's wrong.
	// If `odin check` is alright and you are still receiving this error, please report the issue to the Odin github as it would be an issue with the parser package.
	Invalid_Odin_Code,
	// Attempted to add source with path that was not a directory.
	// Sources only work with entire packages, not individual files.
	// This is not reccomended, but if you really need to scan individual files, use `add_file`.
	Not_A_Directory,
}

// A collection of entries and sources associated with a package name. Used to generate a source code file.
// Prude follows ZII (Zero-Is-Initialization).
// `name` should be set before attempting to write the prelude to a string buffer, and `path` should be set before attempting to write it to a file.
// If `allocator` is not set when the Prelude needs to allocate, `context.allocator` will be used.
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
	// The allocator used to allocate all the strings. Needed for proper destruction.
	allocator :    runtime.Allocator,
}

// Allocates prelude on the heap and initializes it.
prelude_make :: proc(
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	p : ^Prelude,
	err : runtime.Allocator_Error,
) #optional_allocator_error {
	p = new(Prelude, allocator, loc) or_return
	// prelude_init(p, allocator, loc)
	return
}

// Frees prelude and its contained dynamic arrays.
prelude_destroy :: proc(p : ^Prelude) -> runtime.Allocator_Error {
	allocator := p.allocator
	if allocator == {} do return nil
	for entry in p.entries {
		delete(entry.name, allocator) or_return
		delete(entry.source, allocator) or_return
		delete(entry.documentation, allocator) or_return
	}
	delete(p.entries) or_return
	for source in p.sources {
		delete(source.name, allocator) or_return
		delete(source.path, allocator) or_return
	}
	delete(p.sources) or_return
	free(p, allocator) or_return
	return nil
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
