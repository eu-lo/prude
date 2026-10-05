package whens

Outer_Struct :: struct {}

when ODIN_DEBUG {
	@(tag = "prelude")
	Forever_Struct :: struct {}
} else {
	@(tag = "prelude")
	Forever_Struct :: struct {}
}

when ODIN_TEST {
	Sometimes_Struct :: struct {}
}
