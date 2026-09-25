set shell := ["sh", "-c"]

TARGET_DIR := "target"

EXE_NAME := "prude"
DEBUG_EXE_NAME := EXE_NAME + "_debug"

RELEASE_EXE_FILE := TARGET_DIR / EXE_NAME + ".exe"
DEBUG_EXE_FILE := TARGET_DIR / DEBUG_EXE_NAME + ".exe"

COMMON_BUILD_FLAGS := ""

alias bd := build-debug
alias rd := run-debug
alias br := build-release
alias rr := run-release

_default: build-debug
clean:
    rm -rf target
build-debug:
    @mkdir -p {{ TARGET_DIR }}
    odin build . -debug {{ COMMON_BUILD_FLAGS }} -out:{{ DEBUG_EXE_FILE }}
run-debug *ARGS: build-debug
    -{{ DEBUG_EXE_FILE }} {{ ARGS }}
build-release:
    @mkdir -p {{ TARGET_DIR }}
    odin build . {{ COMMON_BUILD_FLAGS }} -o:speed -out:{{ RELEASE_EXE_FILE }}
run-release *ARGS: build-release
    -{{ RELEASE_EXE_FILE }} {{ ARGS }}
check:
    odin check . -debug {{ COMMON_BUILD_FLAGS }}
    odin check . {{ COMMON_BUILD_FLAGS }}
