package prude

import "lib"

import "base:runtime"
import "core:flags"
import "core:log"
import "core:mem"
import "core:os"

Opts :: struct {
	overflow :  [dynamic]string `usage:"Directories to include in the prelude. Does not scan subdirectories."`,
	target :    string `usage:"Output prelude file. Defaults to 'prelude.odin'."`,
	name :      string `usage:"Name of the package. Defaults to directory name."`,
	docs :      ^os.File `args:"file:r" usage:"File to embed into the documentation of the 'package' declaration."`,
	quiet :     bool `usage:"Disable default log output. Setting this implicitly disables '-debug' as well."`,
	debug :     bool `usage:"Enable debug log output."`,
	whitelist : bool `usage:"Treat entries as whitelist rather than blacklist."`,
}

main :: proc() {
	os.exit(run())
}

run :: proc() -> int {
	when ODIN_DEBUG {
		track : mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer mem.tracking_allocator_destroy(&track)
		defer {
			for _, leak in track.allocation_map {
				log.errorf(
					"Leak in (%v %v:%v): %v bytes.",
					leak.location.file_path,
					leak.location.line,
					leak.location.column,
					leak.size,
				)
			}
		}
	}

	opts : Opts
	flags.parse_or_exit(&opts, os.args, .Odin)

	opts_init_defaults(&opts)

	log.debugf("Received opts: %v", opts)

	logger := context.logger
	if !opts.quiet {
		options := log.Options{.Level, .Terminal_Color}
		level : log.Level = .Info
		if opts.debug {
			level = .Debug
			options += {.Short_File_Path, .Line, .Time}
		}
		logger = log.create_console_logger(level, options)
	}
	context.logger = logger

	log.debug("Successfully initialized logging utilities!")

	return execute(opts)
}

// Sets default arguments for options if not specified.
opts_init_defaults :: proc(opts : ^Opts) {
	if opts.quiet do opts.debug = false

	if opts.target == "" {
		opts.target = "prelude.odin"
	}

	if opts.name == "" {
		dir, e := os.get_working_directory(context.allocator)
		if e != nil {
			log.errorf("Could not get working directory: %v, aborting", e)
			return
		}
		opts.name = os.base(dir)
	}
}

execute :: proc(opts : Opts) -> int {
	opts := opts
	defer free_all(context.temp_allocator)
	prelude, perr := lib.prelude_make()
	if perr != nil {
		log.errorf("Error allocating prelude: %v", perr)
		return 3
	}
	defer lib.prelude_destroy(prelude)
	// lib.prelude_init(&prelude)

	if opts.docs != nil {
		docs, e := lib.parse_docs_from_file(opts.docs, context.temp_allocator)
		if e != nil {
			log.warnf("Error parsing docs: %v", e)
			opts.docs = nil
		} else do prelude.docs = docs
	}

	prelude.is_whitelist = opts.whitelist

	prelude.name = opts.name
	prelude.path = opts.target

	had_err := false
	for path in opts.overflow {
		log.infof("Adding source '%v'", path)
		err := lib.add_source(prelude, path)
		if err != nil {
			had_err = true
			log.warnf("Error adding source: %v", err)
			continue
		}
		log.info("Success!")
	}
	if had_err {
		log.error("Encountered errors during source discovery, aborting.")
		return 1
	}

	err := lib.output_to_file(prelude)
	if err != nil {
		log.errorf("Erroring outputting to file: %v, removing output.", err)
		oerr := os.remove(prelude.path)
		if oerr != nil {
			log.errorf("Error removing output: %v, aborting.", oerr)
		}
		return 2
	}
	log.infof("Output successfully written to '%v'.", prelude.path)
	return 0
}
