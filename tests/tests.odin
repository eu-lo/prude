package tests

import "../lib"
import "core:testing"

@(test)
test_declarations :: proc(t : ^testing.T) {
	p, e := lib.prelude_make()
	testing.expect_value(t, e, nil)
	defer lib.prelude_destroy(p)
	defer free_all(context.temp_allocator)

	p.name = "declarations"
	p.path = "prelude.odin"

	se := lib.add_source(p, "tests/files/declarations")
	testing.expect_value(t, se, nil)

	expected_entries := [?]lib.Entry {
		{name = "CONSTANT", source = "declarations.CONSTANT"},
		{name = "Alias", source = "declarations.Alias"},
		{name = "Struct", source = "declarations.Struct"},
		{name = "Enum", source = "declarations.Enum"},
		{name = "Union", source = "declarations.Union"},
		{name = "procedure", source = "declarations.procedure"},
		{name = "uninit_global", source = "declarations.uninit_global"},
		{name = "init_global", source = "declarations.init_global"},
	}

	testing.expect_value(t, len(p.entries), len(expected_entries))

	for i := 0; i < len(p.entries) - 1; i += 1 {
		real := p.entries[i]
		expected := expected_entries[i]
		testing.expect_value(t, real, expected)
	}
}

@(test)
test_renames :: proc(t : ^testing.T) {
	p, e := lib.prelude_make()
	testing.expect_value(t, e, nil)
	defer lib.prelude_destroy(p)
	defer free_all(context.temp_allocator)

	p.name = "renames"
	p.path = "prelude.odin"

	se := lib.add_source(p, "tests/files/renames")
	testing.expect_value(t, se, nil)

	expected_entries := [?]lib.Entry {
		{name = "Int_Alias", source = "renames.Alias"},
		{name = "Struct", source = "renames.Struct"},
	}

	testing.expect_value(t, len(p.entries), len(expected_entries))

	for i := 0; i < len(p.entries) - 1; i += 1 {
		real := p.entries[i]
		expected := expected_entries[i]
		testing.expect_value(t, real, expected)
	}
}

@(test)
test_whitelist :: proc(t : ^testing.T) {
	p, e := lib.prelude_make()
	testing.expect_value(t, e, nil)
	defer lib.prelude_destroy(p)
	defer free_all(context.temp_allocator)

	{
		p.name = "whitelist"
		p.path = "prelude.odin"
		p.is_whitelist = true

		se := lib.add_source(p, "tests/files/whitelist")
		testing.expect_value(t, se, nil)

		expected_entries := [?]lib.Entry {
			{name = "Alias", source = "whitelist.Alias"},
			{name = "Other", source = "whitelist.Other_Alias"},
		}

		testing.expect_value(t, len(p.entries), len(expected_entries))

		for i := 0; i < len(p.entries) - 1; i += 1 {
			real := p.entries[i]
			expected := expected_entries[i]
			testing.expect_value(t, real, expected)
		}
	}

	{
		free_all(context.temp_allocator)
		lib.prelude_destroy(p)
		p = lib.prelude_make()

		p.name = "whitelist"
		p.path = "prelude.odin"

		se := lib.add_source(p, "tests/files/whitelist")
		testing.expect_value(t, se, nil)

		expected_entries := [?]lib.Entry {
			{name = "Alias", source = "whitelist.Alias"},
			{name = "Other", source = "whitelist.Other_Alias"},
			{name = "Struct", source = "whitelist.Struct"},
		}

		testing.expect_value(t, len(p.entries), len(expected_entries))

		for i := 0; i < len(p.entries) - 1; i += 1 {
			real := p.entries[i]
			expected := expected_entries[i]
			testing.expect_value(t, real, expected)
		}
	}
}
