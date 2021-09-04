defmodule Phoenix.PubSub.Nats do
  @moduledoc """
  Phoenix PubSub adapter based on Nats.

  To start it, list it in your supervision tree as:

      {Phoenix.PubSub,
       adapter: Phoenix.PubSub.Nats,
       connection_settings: [%{host: "localhost", port: 4222}],
       node_name: System.get_env("NODE")}

  You will also need to add `:phoenix_pubsub_nats` to your deps:

      defp deps do
        [{:phoenix_pubsub_nats, git: "git://github.com/oskoi/phoenix_pubsub_nats.git"}]
      end

  ## Options

    * `:name` - The required name to register the PubSub processes, ie: `MyApp.PubSub`
    * `:node_name` - The required name of the node, defaults to Erlang --sname flag. It must be unique.
    * `:connection_settings` - The Nats connection settings. See: https://hexdocs.pm/gnat/readme.html#usage
    * `:compression_level` - Compression level applied to serialized terms - from `0` (no compression), to `9` (highest). Defaults `0`

  """
  use Supervisor

  @behaviour Phoenix.PubSub.Adapter

  @connection_name :phx_nats

  @impl true
  defdelegate node_name(adapter_name),
    to: Phoenix.PubSub.NatsServer

  @impl true
  defdelegate broadcast(adapter_name, topic, message, dispatcher),
    to: Phoenix.PubSub.NatsServer

  @impl true
  defdelegate direct_broadcast(adapter_name, node_name, topic, message, dispatcher),
    to: Phoenix.PubSub.NatsServer

  def start_link(opts) do
    adapter_name = Keyword.fetch!(opts, :adapter_name)
    supervisor_name = Module.concat(adapter_name, "Supervisor")
    Supervisor.start_link(__MODULE__, opts, name: supervisor_name)
  end

  @impl true
  def init(opts) do
    pubsub_name = Keyword.fetch!(opts, :name)
    adapter_name = Keyword.fetch!(opts, :adapter_name)
    compression_level = Keyword.get(opts, :compression_level, 0)

    node_name = opts[:node_name] || node()
    validate_node_name!(node_name)

    :ets.new(adapter_name, [:public, :named_table, read_concurrency: true])
    :ets.insert(adapter_name, {:node_name, node_name})
    :ets.insert(adapter_name, {:compression_level, compression_level})

    connection_settings = Keyword.fetch!(opts, :connection_settings)

    gnat_supervisor_settings = %{
      name: @connection_name,
      connection_settings: connection_settings
    }

    children = [
      {Gnat.ConnectionSupervisor, gnat_supervisor_settings},
      {Phoenix.PubSub.NatsServer, {pubsub_name, adapter_name, node_name}},
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp validate_node_name!(node_name) do
    if node_name in [nil, :nonode@nohost] do
      raise ArgumentError, ":node_name is a required option for unnamed nodes"
    end

    :ok
  end
end
