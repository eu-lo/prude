package files

CONSTANT :: 20

Alias :: [2]int

Struct :: struct {
	field : int,
}

Enum :: enum {
	None,
	Entry,
}

Union :: union {
	Struct,
	Enum,
}

procedure :: proc() {
	// ...
}

uninit_global : int

init_global := 30
