## Phoenix.PubSub.Nats

> A Nats PubSub adapter for the Phoenix framework

## Usage

To use Nats as your PubSub adapter, simply add it to your deps and Application's Supervisor tree:

```elixir
# mix.exs
defp deps do
  [{:phoenix_pubsub_nats, git: "git://github.com/oskoi/phoenix_pubsub_nats.git"}],
end

# application.ex
children = [
  # ...,
  {Phoenix.PubSub,
    adapter: Phoenix.PubSub.Nats,
    connection_settings: [%{host: "localhost", port: 4222}],
    node_name: System.get_env("NODE")}
```

Config Options

Option                  | Description                                                                       | Default        |
:-----------------------| :-------------------------------------------------------------------------------- | :------------- |
`:name`                 | The required name to register the PubSub processes, ie: `MyApp.PubSub`            |                |
`:node_name`            | The required and unique name of the node, ie: `System.get_env("NODE")`            |                |
`:connection_settings`  | The Nats connection settings. See: See: https://hexdocs.pm/gnat/readme.html#usage |                |
`:compression_level`    | Compression level applied to serialized terms (`0` - none, `9` - highest)         | `0`            |

And also add `:phoenix_pubsub_nats` to your list of applications:

```elixir
# mix.exs
def application do
  [mod: {MyApp, []},
   applications: [..., :phoenix, :phoenix_pubsub_nats]]
end
```