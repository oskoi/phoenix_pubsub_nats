defmodule Phoenix.PubSub.NatsServer do
  use GenServer
  require Logger

  @nats_msg_vsn 1
  @connection_name :phx_nats

  defp compression_level(adapter_name) do
    :ets.lookup_element(adapter_name, :compression_level, 2)
  end

  defp nats_namespace(adapter_name), do: "phx:#{adapter_name}"

  def node_name(adapter_name) do
    :ets.lookup_element(adapter_name, :node_name, 2)
  end

  def broadcast(adapter_name, topic, message, dispatcher) do
    publish(adapter_name, :except, node_name(adapter_name), topic, message, dispatcher)
  end

  def direct_broadcast(adapter_name, node_name, topic, message, dispatcher) do
    publish(adapter_name, :only, node_name, topic, message, dispatcher)
  end

  defp publish(adapter_name, mode, node_name, topic, message, dispatcher) do
    namespace = nats_namespace(adapter_name)
    compression_level = compression_level(adapter_name)
    nats_msg = {@nats_msg_vsn, mode, node_name, topic, message, dispatcher}
    bin_msg = :erlang.term_to_binary(nats_msg, compressed: compression_level)

    Gnat.pub(@connection_name, namespace, bin_msg)
  end

  def start_link({_, adapter_name, _, _} = state) do
    GenServer.start_link(__MODULE__, state, name: Module.concat(adapter_name, "Server"))
  end

  @impl true
  def init({pubsub_name, adapter_name, node_name}) do
    Process.flag(:trap_exit, true)

    {:ok, task_supervisor_pid} = Task.Supervisor.start_link()

    state = %{
      pubsub_name: pubsub_name,
      adapter_name: adapter_name,
      node_name: node_name,
      connection_pid: nil,
      status: :disconnected,
      subscription: nil,
      task_supervisor_pid: task_supervisor_pid
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: handle_info(:connect, state)

  @impl true
  def handle_info(:connect, %{adapter_name: adapter_name} = state) do
    case Process.whereis(@connection_name) do
      nil ->
        Process.send_after(self(), :connect, 2_000)

        {:noreply, state}

      connection_pid ->
        _ref = Process.monitor(connection_pid)

        {:ok, subscription} = Gnat.sub(connection_pid, self(), nats_namespace(adapter_name))

        state = %{
          state
          | status: :connected,
            connection_pid: connection_pid,
            subscription: subscription
        }

        {:noreply, state}
    end
  end

  def handle_info(
        {:DOWN, _ref, :process, connection_pid, _reason},
        %{connection_pid: connection_pid} = state
      ) do
    Process.send_after(self(), :connect, 2_000)

    state = %{
      state
      | status: :disconnected,
        connection_pid: nil,
        subscription: nil
    }

    {:noreply, state}
  end

  # Ignore DOWN and task result messages from the spawned tasks
  def handle_info({:DOWN, _ref, :process, _task_pid, _reason}, state), do: {:noreply, state}
  def handle_info({ref, _result}, state) when is_reference(ref), do: {:noreply, state}

  def handle_info(
        {:EXIT, supervisor_pid, _reason},
        %{task_supervisor_pid: supervisor_pid} = state
      ) do
    {:ok, task_supervisor_pid} = Task.Supervisor.start_link()

    state = %{state | task_supervisor_pid: task_supervisor_pid}

    {:noreply, state}
  end

  def handle_info(
        {:msg, %{body: body}},
        %{pubsub_name: pubsub_name, node_name: node_name} = state
      ) do
    Task.Supervisor.async_nolink(state.task_supervisor_pid, fn ->
      case :erlang.binary_to_term(body) do
        {@nats_msg_vsn, mode, target_node, topic, message, dispatcher}
        when mode == :only and target_node == node_name
        when mode == :except and target_node != node_name ->
          Phoenix.PubSub.local_broadcast(pubsub_name, topic, message, dispatcher)

        _ ->
          :ignore
      end

      :ok
    end)

    {:noreply, state}
  end

  def handle_info(other, state) do
    Logger.error("#{__MODULE__} received unexpected message #{inspect(other)}")

    {:noreply, state}
  end

  @impl GenServer
  def terminate(:shutdown, state) do
    Logger.info("#{__MODULE__} starting graceful shutdown")

    :ok = Gnat.unsub(state.connection_pid, state.subscription)

    # wait for final messages from broker
    Process.sleep(500)

    receive_final_broker_messages(state)
    wait_for_empty_task_supervisor(state)

    Logger.info("#{__MODULE__} finished graceful shutdown")
  end

  def terminate(reason, _state) do
    Logger.error("#{__MODULE__} unexpected shutdown #{inspect(reason)}")
  end

  defp receive_final_broker_messages(state) do
    receive do
      info ->
        handle_info(info, state)
        receive_final_broker_messages(state)
    after
      0 ->
        :done
    end
  end

  defp wait_for_empty_task_supervisor(%{task_supervisor_pid: pid} = state) do
    case Task.Supervisor.children(pid) do
      [] ->
        :ok

      children ->
        Logger.info("#{__MODULE__}\t\t#{Enum.count(children)} tasks remaining")
        Process.sleep(1_000)
        wait_for_empty_task_supervisor(state)
    end
  end
end
