defmodule GuessTheSong.Voice.Server do
  use GenServer, restart: :temporary

  alias Nostrum.Voice

  # --- Public API ---

  @doc "Joins the voice channel, sending `:voice_ready` to `notify` once connected."
  def start_link({guild_id, channel_id, notify}) do
    GenServer.start_link(__MODULE__, {guild_id, channel_id, notify}, name: via(guild_id))
  end

  @doc "Leaves the voice channel for the given guild."
  def leave(guild_id), do: GenServer.cast(via(guild_id), :leave)

  @doc """
  Plays audio in the voice channel. Type is a Nostrum play type e.g. :url,
  :ytdl. Returns straight away; a failure to play is logged.
  """
  def play_audio(guild_id, input, type \\ :url, opts \\ []) do
    GenServer.cast(via(guild_id), {:play_audio, input, type, opts})
  end

  @doc "Stops the currently playing audio."
  def stop_audio(guild_id), do: GenServer.cast(via(guild_id), :stop_audio)

  @doc """
  Tells the session the bot is no longer in the voice channel (e.g. it was
  kicked), so the session stops. Anything monitoring the session, like a quiz,
  sees it go down.
  """
  def disconnected(guild_id), do: GenServer.cast(via(guild_id), :disconnected)

  # --- Private ---

  defp via(guild_id) do
    {:via, Registry, {GuessTheSong.Voice.Registry, guild_id}}
  end

  # --- GenServer callbacks ---

  @impl true
  def init({guild_id, channel_id, notify}) do
    case Voice.join_channel(guild_id, channel_id, false, true, false) do
      :ok ->
        {:ok, %{guild_id: guild_id, channel_id: channel_id, notify: notify},
         {:continue, :wait_for_ready}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:wait_for_ready, state) do
    receive do
      :voice_ready ->
        send(state.notify, :voice_ready)
        {:noreply, state}
    after
      10_000 -> {:stop, :voice_ready_timeout, state}
    end
  end

  @impl true
  def handle_cast({:play_audio, input, type, opts}, state) do
    case Voice.play(state.guild_id, input, type, opts) do
      {:error, reason} -> IO.inspect(reason, label: "Failed to play audio")
      _ -> :ok
    end

    {:noreply, state}
  end

  def handle_cast(:stop_audio, state) do
    Voice.stop(state.guild_id)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:leave, state) do
    {:stop, :normal, state}
  end

  # A `:shutdown` reason, so it isn't logged as a crash
  def handle_cast(:disconnected, state) do
    {:stop, {:shutdown, :disconnected}, state}
  end

  @impl true
  def terminate(_reason, state) do
    Voice.leave_channel(state.guild_id)
  end
end
