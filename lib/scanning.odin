package core

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:strings"

// Zero-initializes prelude. Allocates dynamic arrays for the entries and sources using provided allocator.
// You should also set `name` and `path` after calling this.
prelude_init :: proc(
	p : ^Prelude,
	allocator := context.allocator,
	loc := #caller_location,
) -> runtime.Allocator_Error {
	p^ = {}
	p.entries = make([dynamic]Entry, allocator, loc) or_return
	p.sources = make([dynamic]Source, allocator, loc) or_return
	return nil
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
	prelude_init(p) or_return
	return p, err
}

// Frees prelude its contained dynamic arrays.
prelude_destroy :: proc(
	p : ^Prelude,
	allocator := context.allocator,
	loc := #caller_location,
) -> runtime.Allocator_Error {
	assert(p != nil)
	delete(p.entries, loc) or_return
	delete(p.sources, loc) or_return
	free(p, allocator, loc) or_return
	return nil
}

// Parses a string into an odin-compliant docstring, ideally to be placed into a `Prelude`.
//
// ## Allocations
// The returned string is allocated with `allocator` must be freed by the caller.
// Additionally the internal string builder is allocated and freed with `context.temp_allocator`
parse_docs :: proc(
	docs : string,
	allocator := context.allocator,
) -> (
	res : string,
	err : Error,
) {
	defer free_all(context.temp_allocator)

	log.debugf("Parsing docs:\n%v", docs)
	buf := strings.builder_make(context.temp_allocator) or_return
	lines := strings.split_lines(
		strings.trim_space(docs),
		context.temp_allocator,
	) or_return
	for line in lines {
		strings.write_string(&buf, "// ")
		strings.write_string(&buf, line)
		strings.write_byte(&buf, '\n')
	}
	result := strings.clone(strings.to_string(buf), allocator)
	log.debugf("Resulting documentation:\n%v", result)

	return result, nil
}

// Parses docs as according to `parse_docs` but from a file handle.
//
// ## Allocations
// This is a wrapper over `parse_docs` and as such also returns a string that must be freed.
// It allocates in all the same ways.
// If logging allows, it also uses `allocator` to allocate the file stats for debugging.
parse_docs_from_file :: proc(
	file : ^os.File,
	allocator := context.allocator,
) -> (
	res : string,
	err : Error,
) {
	log.ensure(file != nil)
	defer free_all(context.temp_allocator)

	if context.logger.lowest_level == .Debug {
		// No need to allocate if the log won't be printed
		info := os.fstat(file, context.allocator) or_return
		defer os.file_info_delete(info, context.allocator)
		log.infof("Parsing docs from file: %q", info.fullpath)
	}

	data := os.read_entire_file(file, context.temp_allocator) or_return
	content := string(data)
	return parse_docs(content)
}

// Writes prelude to file specified in `prelude.path`.
prelude_output_to_file :: proc(p : ^Prelude) -> Error {
	assert(p != nil)
	output := strings.builder_make(context.allocator) or_return
	defer strings.builder_destroy(&output)
	write_package(&output, p)
	os.write_entire_file(p.path, output.buf[:]) or_return
	return nil
}

// Writes prelude output to string.
//
// ## Allocations
// This allocates a strings.Builder using the provided allocator.
// The returned string needs to be freed by the caller.
prelude_output_to_string :: proc(
	p : ^Prelude,
	allocator := context.allocator,
) -> (
	res : string,
	err : runtime.Allocator_Error,
) {
	assert(p != nil)
	output := strings.builder_make(allocator) or_return
	defer strings.builder_destroy(&output)
	write_package(&output, p)
	return strings.clone(strings.to_string(output), allocator)
}

// Adds source to prelude using a specified path to directory.
// `path` should be a directory.
prelude_add_source :: proc(p : ^Prelude, path : string) -> Error {
	assert(p != nil)
	dir := os.open(path) or_return
	info := os.stat(path, context.temp_allocator) or_return
	defer os.file_info_delete(info, context.temp_allocator)
	if info.type != .Directory do return .Not_A_Directory

	// TODO: Handle duplicate source names
	name := strings.clone(info.name)
	path := os.join_path({os.dir(p.path), path}, context.allocator) or_return

	source := Source {
		name = name,
		path = path,
	}
	log.debugf("New source: %v", source)

	files := os.read_directory(dir, -1, context.allocator) or_return
	for file in files {
		if file.type != .Regular do continue

		fext := os.ext(file.fullpath)
		if fext != ".odin" do continue

		f := os.open(file.fullpath) or_return
		prelude_add_file(p, &source, f)
	}
	os.file_info_slice_delete(files, context.allocator)

	append(&p.sources, source) or_return

	return nil
}

prelude_add_file :: proc(
	p : ^Prelude,
	source : ^Source,
	file : ^os.File,
) -> Error {
	assert(p != nil)
	info := os.fstat(file, context.temp_allocator) or_return
	fext := os.ext(info.fullpath)
	if info.type != .Regular do return .Not_A_File
	if fext != ".odin" do return .Non_Odin_File

	log.debugf("Adding file '%v'", info.fullpath)

	data := os.read_entire_file(file, context.temp_allocator) or_return

	ast_parser : parser.Parser
	ast_file := ast.File {
		src      = string(data),
		fullpath = info.fullpath,
	}
	parse_ok := parser.parse_file(&ast_parser, &ast_file)
	if !parse_ok {
		return .Invalid_Odin_Code
	}
	for decl in ast_file.decls {
		__process_decl(p, data, decl, source) or_return
	}

	free_all(context.temp_allocator)
	return nil
}

// Processes a declaration (produced by core:odin/parser) and adds an entry to the given `Prelude`.
//
// ## Allocations
// This procedure allocates a `strings.Builder` using `context.temp_allocator`.
// It also clones a few strings using `context.temp_allocator`.
// If successful, the strings that are stored in the prelude entry get cloned using `context.allocator`.
//
// ## Safety
// This procedure assumes that the given byte slice is valid UTF-8, and that the given ast node was produced without errors.
@(tag = "prelude:_")
__process_decl :: proc(
	p : ^Prelude,
	data : []byte,
	decl : ^ast.Stmt,
	source : ^Source,
) -> (
	err : Error,
) {
	assert(p != nil)
	log.debugf("Begin processing declaration")
	value, ok := decl.derived_stmt.(^ast.Value_Decl)
	if !ok do return
	assert(len(value.names) > 0)
	expr := value.names[0]
	target := strings.clone(
		string(data[expr.pos.offset:expr.end.offset]),
		context.temp_allocator,
	)
	name := target
	log.debugf("Extracted name/target: %v", name)

	docs_buf := strings.builder_make(context.temp_allocator)
	// Gets freed by caller
	if value.docs != nil {
		for tok in value.docs.list {
			strings.write_string(&docs_buf, tok.text)
			strings.write_byte(&docs_buf, '\n')
		}
	}
	docs := strings.to_string(docs_buf)
	log.debugf("Extracted docs: %w", docs)

	allow := !p.is_whitelist
	for attr in value.attributes {
		for elem in attr.elems {
			#partial switch fv in elem.derived {
			case ^ast.Ident:
				if fv.name == "private" do return
			case ^ast.Field_Value:
				ident := fv.field.derived.(^ast.Ident) or_continue
				ident_name := ident.name
				if ident_name == "private" do return

				content_lit := fv.value.derived.(^ast.Basic_Lit)
				content := content_lit.tok.text[1:len(content_lit.tok.text) - 1]
				if p.is_whitelist && content == "prelude" do allow = true
				extract := strings.split(content, ":", context.temp_allocator)
				if len(extract) != 2 do continue
				prefix := extract[0]
				suffix := extract[1]

				if prefix != "prelude" do continue
				if suffix == "_" do return
				allow = true

				name = strings.clone(suffix, context.temp_allocator)
				log.debugf("Found new name: %v", name)
			}
		}
	}
	if !allow do return

	name = strings.clone(name, context.allocator)
	docs = strings.clone(docs, context.allocator)
	source := fmt.aprintf(
		"%v.%v",
		source.name,
		target,
		allocator = context.allocator,
	)
	log.debugf("Composed source: %v", source)

	entry := Entry {
		name          = name,
		source        = source,
		documentation = docs,
	}

	append(&p.entries, entry)
	log.debug("Successfully added entry")

	return nil
}
