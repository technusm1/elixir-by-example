---
title: "Integrating Other Languages with Elixir"
---
{% contentfor sidebar %}
While Elixir excels at concurrent and distributed systems, sometimes you need to tap into other languages for CPU-intensive tasks or to leverage existing libraries. Elixir provides several ways to integrate with other languages.
{% endcontentfor %}

## Integration Methods

- **NIFs (Native Implemented Functions)**: Direct integration with C/Rust, highest performance
- **Ports**: Safe, isolated communication with external programs
- **Port Drivers**: Legacy method, prefer NIFs or Ports for new code
- **C Nodes**: Separate processes communicating via Erlang distribution protocol

## Rust Integration

Rust is the most ergonomic choice for writing NIFs, thanks to the [Rustler](https://github.com/rusterlium/rustler) library. It provides memory safety and excellent performance.

```elixir
# In mix.exs
def deps do
  [
    {:rustler, "~> 0.30.0"}
  ]
end

# In lib/native.ex
defmodule MyApp.Native do
  use Rustler, otp_app: :my_app, crate: "native"

  # These functions are implemented in Rust
  def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def fibonacci(_n), do: :erlang.nif_error(:nif_not_loaded)
end
```

```rust
// In native/native/src/lib.rs
#[rustler::nif]
fn add(a: i64, b: i64) -> i64 {
    a + b
}

#[rustler::nif]
fn fibonacci(n: i64) -> i64 {
    match n {
        0 | 1 => n,
        _ => fibonacci(n - 1) + fibonacci(n - 2)
    }
}

rustler::init!("Elixir.MyApp.Native", [add, fibonacci]);
```

## C Integration with NIFs

NIFs with C require more careful memory management but offer maximum performance.

```elixir
# In lib/nif.ex
defmodule MyApp.Nif do
  @on_load :load_nifs

  def load_nifs do
    :erlang.load_nif('./priv/nif', 0)
  end

  def calculate_square(_x), do: raise "NIF not loaded"
end
```

```c
// In c_src/nif.c
#include "erl_nif.h"

static ERL_NIF_TERM calculate_square(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    int x;
    if (!enif_get_int(env, argv[0], &x)) {
        return enif_make_badarg(env);
    }
    return enif_make_int(env, x * x);
}

static ErlNifFunc nif_funcs[] = {
    {"calculate_square", 1, calculate_square}
};

ERL_NIF_INIT(Elixir.MyApp.Nif, nif_funcs, NULL, NULL, NULL, NULL)
```

## Python Integration

Python integration typically uses Ports for safety and simplicity:

```elixir
defmodule MyApp.Python do
  def run_script(script, args) do
    port = Port.open({:spawn, "python3 #{script} #{args}"}, [:binary])
    receive do
      {^port, {:data, result}} -> {:ok, result}
      other -> {:error, other}
    end
  end
  
  # Example: Call a Python ML model
  def predict(data) do
    run_script("predict.py", Jason.encode!(data))
  end
end
```

```python
# predict.py
import sys
import json
from my_ml_model import predict

input_data = json.loads(sys.argv[1])
result = predict(input_data)
print(json.dumps(result))
```

## Zig Integration

Zig provides a modern alternative to C for writing NIFs, with better safety features:

```zig
// In src/main.zig
const std = @import("std");
const beam = @import("beam");

export fn add(env: beam.env, argc: c_int, argv: [*c]const beam.term) beam.term {
    var a: i64 = undefined;
    var b: i64 = undefined;
    
    beam.get_i64(env, argv[0], &a) catch return beam.raise_badarg(env);
    beam.get_i64(env, argv[1], &b) catch return beam.raise_badarg(env);
    
    return beam.make_i64(env, a + b);
}
```

## Best Practices

✅ **Do:**
- Use Rustler for new NIF development when possible
- Implement CPU-intensive or memory-heavy operations in NIFs
- Keep NIF execution time short to avoid blocking the BEAM
- Use Ports for potentially unstable integrations

❌ **Don't:**
- Write NIFs in C unless absolutely necessary
- Run long-running operations in NIFs
- Pass large data structures through Ports
- Forget to handle crashes in external code

## Performance Considerations

| Method | Performance | Safety | Use Case |
|--------|------------|---------|----------|
| NIFs   | Fastest    | Unsafe  | CPU-intensive, small operations |
| Ports  | Moderate   | Safe    | I/O, external services |
| C Nodes | Slow      | Safe    | Distributed systems |

## Common Pitfalls

- **NIF Crashes**: Can bring down the entire BEAM VM
- **Memory Leaks**: Common in C NIFs, less likely with Rust
- **Port Bottlenecks**: Large data transfers can be slow
- **Version Mismatches**: External dependencies need careful management
