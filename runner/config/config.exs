import Config

# Tree-shaking stays off: readers can edit and run arbitrary code, so the whole
# standard library must be present.
config :popcorn, treeshake: false
