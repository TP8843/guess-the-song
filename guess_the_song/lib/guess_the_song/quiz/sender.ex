defmodule GuessTheSong.Quiz.Sender do
  @moduledoc """
  Posts a quiz's Discord messages one at a time, in order, so the quiz never
  waits on Discord (e.g. when its rate limit holds a message back).

  The sender monitors the quiz instead of being linked to it. When the quiz
  stops, the `:DOWN` message arrives after every message the quiz posted, so
  the sender sends what's left (like the final scores) and then exits.
  """

  @doc """
  Starts a sender for `owner`. `send_fun` makes the actual request, and can be
  replaced in tests.
  """
  @spec start(pid(), (integer(), keyword() -> term())) :: {:ok, pid()}
  def start(owner, send_fun \\ &Nostrum.Api.Message.create/2) do
    Task.Supervisor.start_child(GuessTheSong.Quiz.TaskSupervisor, fn ->
      loop(Process.monitor(owner), send_fun)
    end)
  end

  @doc "Queues a message for the channel. Returns straight away."
  @spec post(pid(), integer(), keyword()) :: :ok
  def post(sender, channel_id, opts) do
    send(sender, {:post, channel_id, opts})
    :ok
  end

  defp loop(owner_ref, send_fun) do
    receive do
      {:post, channel_id, opts} ->
        deliver(send_fun, channel_id, opts)
        loop(owner_ref, send_fun)

      {:DOWN, ^owner_ref, :process, _pid, _reason} ->
        drain(send_fun)
    end
  end

  # Sends anything still queued after the quiz stopped
  defp drain(send_fun) do
    receive do
      {:post, channel_id, opts} ->
        deliver(send_fun, channel_id, opts)
        drain(send_fun)
    after
      0 -> :ok
    end
  end

  # A failed message is logged and skipped, so later ones still go out
  defp deliver(send_fun, channel_id, opts) do
    case send_fun.(channel_id, opts) do
      {:error, reason} -> IO.inspect(reason, label: "Failed to send quiz message")
      _ -> :ok
    end
  catch
    kind, reason -> IO.inspect({kind, reason}, label: "Failed to send quiz message")
  end
end
