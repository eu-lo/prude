package core

// TODO: refactor procedures, reduce "abstraction meddling"

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:strings"

// Derives a "package name" from sections of a path.
// It joins, up to `level - 1` parts, subdirectory names with underscores, walking bottom-up from the deepest subdirectory to the thinnest.
// This is used to disambiguate import names if they end up colliding.
@(tag = "prelude:_")
name_from_path :: proc(
	path : string,
	level : int,
	allocator := context.allocator,
) -> (
	name : string,
	ok : bool,
) {
	level := level
	ok = true
	path_parts := strings.split(
		path,
		os.Path_Separator_String,
		context.temp_allocator,
	)
	level = len(path_parts) - level - 1
	if level < 0 {
		ok = false
		level = 0
	}
	parts := path_parts[level:]
	name = strings.join(parts, "_", allocator)
	return
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
output_to_file :: proc(p : ^Prelude) -> Error {
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
output_to_string :: proc(
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

// Ensures ZII. Needs to be run anytime a prelude may allocate.
@(private)
__prelude_init :: proc(p : ^Prelude) {
	if p.allocator == {} do p.allocator = context.allocator
	if p.sources.allocator == {} do p.sources.allocator = p.allocator
	if p.entries.allocator == {} do p.entries.allocator = p.allocator
}

@(tag = "prelude:_")
__get_info_and_initial_path :: proc(
	home_path : string,
	source_path : string,
) -> (
	info : os.File_Info,
	joined_path : string,
	err : Error,
) {
	info = os.stat(source_path, context.temp_allocator) or_return
	if info.type != .Directory do return {}, "", .Not_A_Directory

	joined_path = os.join_path(
		{os.dir(home_path), source_path},
		context.temp_allocator,
	) or_return

	return info, joined_path, nil
}

@(tag = "prelude:_")
__scan_source :: proc(p : ^Prelude, path : string, source : ^Source) -> Error {
	dir := os.open(path) or_return
	files := os.read_directory(dir, -1, context.temp_allocator) or_return
	for file in files {
		if file.type != .Regular do continue

		fullpath := file.fullpath

		fext := os.ext(fullpath)
		if fext != ".odin" do continue

		old_whitelisted := p.is_whitelist
		if is_path_default_whitelisted(fullpath) {
			p.is_whitelist = true
		}
		f := os.open(fullpath) or_return
		add_file(p, source, f)
		p.is_whitelist = old_whitelisted
	}
	return nil
}

is_path_default_whitelisted :: proc(path : string) -> bool {
	fstem := os.stem(path)
	// Names sourced from https://github.com/odin-lang/Odin/blob/master/src/build_settings.cpp
	// I believe this includes all file suffixes.
	if strings.ends_with(fstem, "_windows") do return true
	if strings.ends_with(fstem, "_darwin") do return true
	if strings.ends_with(fstem, "_linux") do return true
	if strings.ends_with(fstem, "_freebsd") do return true
	if strings.ends_with(fstem, "_openbsd") do return true
	if strings.ends_with(fstem, "_netbsd") do return true
	if strings.ends_with(fstem, "_wasi") do return true
	if strings.ends_with(fstem, "_js") do return true
	if strings.ends_with(fstem, "_orca") do return true
	if strings.ends_with(fstem, "_freestanding") do return true

	// Architecture suffixes
	if strings.ends_with(fstem, "_amd64") do return true
	if strings.ends_with(fstem, "_i386") do return true
	if strings.ends_with(fstem, "_arm32") do return true
	if strings.ends_with(fstem, "_arm64") do return true
	if strings.ends_with(fstem, "_wasm32") do return true
	if strings.ends_with(fstem, "_wasm64p32") do return true
	if strings.ends_with(fstem, "_riscv64") do return true
	return false
}

// Adds source to prelude using a specified path to directory.
// `path` should be a directory.
add_source :: proc(p : ^Prelude, path : string) -> Error {
	assert(p != nil)
	__prelude_init(p)

	info, joined_path := __get_info_and_initial_path(p.path, path) or_return
	name, ok := name_from_path(joined_path, 0, p.allocator)
	assert(ok) // name_from_path() can't fail for level == 0, since len(x) is always over 0.

	// Resolve name conflicts.
	level, idx : int
	outer: for {
		// There are only a few sources at a time, so a linear search is fine.
		for source in p.sources {
			if source.name == name {
				level += 1
				name, ok = name_from_path(joined_path, level, p.allocator)
				if !ok {
					idx += 1
					name = fmt.aprint(name, idx, sep = "", allocator = p.allocator)
				}
				log.warnf(
					"Source '%v' (at '%v') has name collision, resolved to '%v'",
					source.name,
					joined_path,
					name,
				)
				continue outer
			}
		}
		break
	}

	was_alloc : bool
	joined_path, was_alloc = strings.replace(
		joined_path,
		os.Path_Separator_String,
		"/",
		-1,
		allocator = p.allocator,
	)
	// If it wasn't an allocation, the string lives in temp_allocator and needs to be copied out.
	if !was_alloc do joined_path = strings.clone(joined_path, p.allocator)

	source := Source {
		name = name,
		path = joined_path,
	}
	log.debugf("New source: %v", source)

	__scan_source(p, path, &source) or_return

	append(&p.sources, source)

	return nil
}

add_file :: proc(p : ^Prelude, source : ^Source, file : ^os.File) -> Error {
	assert(p != nil)
	__prelude_init(p)

	info := os.fstat(file, context.temp_allocator) or_return
	fext := os.ext(info.fullpath)
	if info.type != .Regular do return .Not_A_File
	if fext != ".odin" do return .Non_Odin_File

	log.debugf("Adding file '%v'", info.fullpath)

	data := os.read_entire_file(file, context.temp_allocator) or_return

	ast_parser : parser.Parser
	ast_file : ast.File
	{
		// Otherwise there is no way to cleanly free the parser lmao
		context.allocator = context.temp_allocator
		ast_file = ast.File {
			src      = string(data),
			fullpath = info.fullpath,
		}
		parse_ok := parser.parse_file(&ast_parser, &ast_file)
		if !parse_ok {
			return .Invalid_Odin_Code
		}
	}
	for decl in ast_file.decls {
		__process_decl(p, data, decl, source) or_return
	}

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
	assert(decl != nil)
	assert(source != nil)
	__prelude_init(p)

	log.debugf("Begin processing declaration")
	if stmt, ok := decl.derived_stmt.(^ast.When_Stmt); ok {
		log.debug("Found when statement")
		block, bok := stmt.body.derived.(^ast.Block_Stmt)
		if !bok do return
		else_stmt : Maybe(^ast.Block_Stmt)
		if stmt.else_stmt != nil {
			eok : bool
			else_stmt, eok = stmt.else_stmt.derived.(^ast.Block_Stmt)
			if !eok { else_stmt = nil }
		}
		old_whitelist := p.is_whitelist
		defer p.is_whitelist = old_whitelist
		p.is_whitelist = true
		for stmt in block.stmts {
			e := __process_decl(p, data, stmt, source)
			if e != nil do return e
		}
		switch eblock in else_stmt {
		case ^ast.Block_Stmt:
			for stmt in eblock.stmts {
				e := __process_decl(p, data, stmt, source)
				if e != nil do return e
			}
		}
		return
	}
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

	name = strings.clone(name, p.allocator)
	docs = strings.clone(docs, p.allocator)
	source_name := fmt.aprintf(
		"%v.%v",
		source.name,
		target,
		allocator = p.allocator,
	)
	log.debugf("Composed source: %v", source_name)

	for entry in p.entries {
		if entry.name == name {
			if entry.source == source_name {
				delete(name, p.allocator)
				delete(docs, p.allocator)
				delete(source_name, p.allocator)
				return
			}
			old_name := name
			name = fmt.aprint(
				source.name,
				"_",
				name,
				sep = "",
				allocator = p.allocator,
			)
			log.warnf(
				"Entry '%v' (in '%v') had name collision, resolved to '%v'. Consider manually renaming this entry.",
				old_name,
				source.name,
				name,
			)
			delete(old_name, p.allocator)
		}
	}

	entry := Entry {
		name          = name,
		source        = source_name,
		documentation = docs,
	}

	append(&p.entries, entry)
	log.debug("Successfully added entry")

	return nil
}
