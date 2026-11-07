# Many Elixir functions return tagged tuples:
# `{:ok, value}` on success and `{:error, reason}` on
# failure. `with` chains several such steps and stops
# at the first one that doesn't match.
defmodule Signup do
  def parse_age(input) do
    case Integer.parse(input) do
      {age, ""} -> {:ok, age}
      _ -> {:error, :not_a_number}
    end
  end

  def check_adult(age) when age >= 18, do: {:ok, age}
  def check_adult(_age), do: {:error, :too_young}

  def check_email(email) do
    if String.contains?(email, "@"), do: {:ok, email}, else: {:error, :bad_email}
  end

  # Each `pattern <- expression` clause must match to
  # continue. The `do` block runs only if all match.
  def run(params) do
    with {:ok, age} <- parse_age(params["age"]),
         {:ok, age} <- check_adult(age),
         {:ok, email} <- check_email(params["email"]) do
      {:ok, %{age: age, email: email}}
    end
  end
end

# On the happy path, every step matches.
IO.inspect(Signup.run(%{"age" => "30", "email" => "ada@example.com"}))

# Without an `else`, the first non-matching value is
# returned as-is, so errors pass straight through.
IO.inspect(Signup.run(%{"age" => "abc", "email" => "ada@example.com"}))
IO.inspect(Signup.run(%{"age" => "12", "email" => "ada@example.com"}))
IO.inspect(Signup.run(%{"age" => "30", "email" => "nope"}))

# `else` lets you translate failures, for example
# into messages for a user. Its clauses match the
# value that broke the chain.
explain = fn params ->
  with {:ok, age} <- Signup.parse_age(params["age"]),
       {:ok, _} <- Signup.check_adult(age) do
    "welcome"
  else
    {:error, :not_a_number} -> "age must be a number"
    {:error, :too_young} -> "come back when you're 18"
  end
end

IO.puts(explain.(%{"age" => "40"}))
IO.puts(explain.(%{"age" => "x"}))
IO.puts(explain.(%{"age" => "9"}))

# Plain `=` matches work inside `with` too, for
# intermediate values that can't fail.
result =
  with {:ok, n} <- {:ok, 21},
       doubled = n * 2 do
    doubled
  end

IO.inspect(result, label: "plain match")

# > **Pitfall:** a long `else` that matches every
# > possible error from every step couples the caller
# > to all of them. It's usually better to make each
# > step return a descriptive `{:error, reason}` and
# > let it pass through untouched.
#
# > **Pitfall:** if no `else` clause matches, `with`
# > raises `WithClauseError`. Once you add `else`,
# > cover every failure shape the steps can return.
