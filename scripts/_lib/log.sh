#!/usr/bin/env bash
# Logging helpers. stdout is reserved for tool/hook output (JSON); everything
# diagnostic goes to stderr so it never corrupts a hook response or a captured view.

iroha_log() { printf 'iroha: %s\n' "$*" >&2; }
iroha_warn() { printf 'iroha[warn]: %s\n' "$*" >&2; }
iroha_err() { printf 'iroha[error]: %s\n' "$*" >&2; }
