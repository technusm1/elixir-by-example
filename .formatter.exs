[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs,heex}",
    "examples/**/*.exs",
    "projects/**/*.exs",
    "runner/{mix,.formatter}.exs",
    "runner/{config,lib}/**/*.{ex,exs}"
  ]
]
