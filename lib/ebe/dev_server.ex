defmodule Ebe.DevServer do
  @moduledoc false
  # Dev-only static server that mirrors Cloudflare's behaviour closely enough:
  # extensionless URLs resolve to `.html`, and the Popcorn headers are set.

  use Plug.Builder

  @dist Path.expand("../../dist", __DIR__)

  plug :headers
  plug :rewrite
  plug Plug.Static, at: "/", from: @dist, gzip: false
  plug :not_found

  defp headers(conn, _opts) do
    conn
    |> put_resp_header("cross-origin-opener-policy", "same-origin")
    |> put_resp_header("cross-origin-embedder-policy", "require-corp")
    |> put_resp_header("cache-control", "no-store")
  end

  defp rewrite(%Plug.Conn{path_info: []} = conn, _opts), do: %{conn | path_info: ["index.html"]}

  defp rewrite(%Plug.Conn{path_info: path_info} = conn, _opts) do
    rel = Path.join(path_info)

    if Path.extname(rel) == "" and File.regular?(Path.join(@dist, rel <> ".html")) do
      %{conn | path_info: List.update_at(path_info, -1, &(&1 <> ".html"))}
    else
      conn
    end
  end

  defp not_found(conn, _opts) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(404, File.read!(Path.join(@dist, "404.html")))
    |> halt()
  end
end
