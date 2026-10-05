TARGET_DIR := "target"

EXE_NAME := "prude"
DEBUG_EXE_NAME := EXE_NAME + "_debug"

RELEASE_EXE_FILE := TARGET_DIR / EXE_NAME + ".exe"
DEBUG_EXE_FILE := TARGET_DIR / DEBUG_EXE_NAME + ".exe"

COMMON_BUILD_FLAGS := "-vet-style -vet-semicolon -vet-shadowing"

alias bd := build-debug
alias rd := run-debug
alias br := build-release
alias rr := run-release

alias build := build-release

_default:
    @just --list

# Cleans build directory and prelude file. Necessary to run before building, as an incorrect prelude file can mistakenly halt builds.
clean:
    rm -f prelude.odin
    rm -rf target

# Runs all library tests
test: clean
    odin test tests -define:ODIN_TEST_THREADS=1

# Builds project in debug mode.
build-debug: clean
    @mkdir -p {{ TARGET_DIR }}
    odin build . -debug {{ COMMON_BUILD_FLAGS }} -out:{{ DEBUG_EXE_FILE }}

# Runs prude using provided arguments.
run-debug *ARGS: build-debug
    -{{ DEBUG_EXE_FILE }} {{ ARGS }}

# Builds project in release mode.
build-release:
    @mkdir -p {{ TARGET_DIR }}
    odin build . {{ COMMON_BUILD_FLAGS }} -o:speed -out:{{ RELEASE_EXE_FILE }}

# Runs project in release mode.
run-release *ARGS: build-release
    -{{ RELEASE_EXE_FILE }} {{ ARGS }}

# Lints project using odin's standard linter.
check:
    odin check . -debug {{ COMMON_BUILD_FLAGS }}
    odin check . {{ COMMON_BUILD_FLAGS }}
