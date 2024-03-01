const std = @import("std");

// Importing the Erlang NIF header, which contains the definitions for the Erlang
// NIF API.
const erl = @cImport({
    @cInclude("erl_nif.h");
});

/// NIF function that simply adds two numbers. This is for test purpose
///
/// - env: a pointer to an `ErlNifEnv` struct, which contains the environment
///        for the NIF. This struct is used to allocate memory, create Erlang
///        terms, and more.
/// - argc: the number of arguments passed to the NIF.
/// - argv: array of Erlang terms (the arguments passed to the NIF).
export fn nif_add(
    env: ?*erl.ErlNifEnv,
    argc: c_int,
    argv: [*c]const erl.ERL_NIF_TERM,
) erl.ERL_NIF_TERM {
    var a: i32 = undefined;
    var b: i32 = undefined;

    if ((argc != 2)) {
        return erl.enif_make_badarg(env);
    }

    _ = erl.enif_get_int(env, argv[0], &a);
    _ = erl.enif_get_int(env, argv[1], &b);

    const result = a + b;
    return erl.enif_make_int(env, result);
}

/// This constant represents the number of NIF functions defined.
const func_count = 1;

/// An array the represents the NIF functions in the library.
/// Contains the name of the function, its arity, and other information regarding
/// the function itself.
var funcs = [func_count]erl.ErlNifFunc{
    erl.ErlNifFunc{
        .name = "nif_add",
        .arity = 2,
        .fptr = nif_add,
        .flags = 0,
    },
};

/// This struct is used to register the NIFs into the Erlang VM.
var entry = erl.ErlNifEntry{
    .major = erl.ERL_NIF_MAJOR_VERSION,
    .minor = erl.ERL_NIF_MINOR_VERSION,
    .name = "Elixir.ExampleNif",
    .num_of_funcs = func_count,
    .funcs = &funcs,
    .load = null,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = "beam.vanilla",
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(erl.ErlNifResourceTypeInit),
    .min_erts = "erts-10.4",
};

export fn nif_init() *erl.ErlNifEntry {
    return &entry;
}
