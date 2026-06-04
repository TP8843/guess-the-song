defmodule GuessTheSong.Voice.Server do
  use GenServer, restart: :temporary

  alias Nostrum.Voice

  # --- Public API ---

  def start_link({guild_id, channel_id}) do
    GenServer.start_link(__MODULE__, {guild_id, channel_id}, name: via(guild_id))
  end

  @doc "Leaves the voice channel for the given guild."
  def leave(guild_id), do: GenServer.cast(via(guild_id), :leave)

  @doc "Plays audio in the voice channel. Type is a Nostrum play type e.g. :url, :ytdl."
  def play_audio(guild_id, input, type \\ :url, opts \\ []) do
    GenServer.call(via(guild_id), {:play_audio, input, type, opts})
  end

  @doc "Stops the currently playing audio."
  def stop_audio(guild_id), do: GenServer.cast(via(guild_id), :stop_audio)

  # --- Private ---

  defp via(guild_id) do
    {:via, Registry, {GuessTheSong.Voice.Registry, guild_id}}
  end

  # --- GenServer callbacks ---

  @impl true
  def init({guild_id, channel_id}) do
    case Voice.join_channel(guild_id, channel_id, false, true, false) do
      :ok -> {:ok, %{guild_id: guild_id, channel_id: channel_id}, {:continue, :wait_for_ready}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:wait_for_ready, state) do
    receive do
      :voice_ready -> {:noreply, state}
      after 10_000 -> {:stop, :voice_ready_timeout, state}
    end
  end

  @impl true
  def handle_call({:play_audio, input, type, opts}, _from, state) do
    result = Voice.play(state.guild_id, input, type, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_cast(:stop_audio, state) do
    Voice.stop(state.guild_id)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:leave, state) do
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    Voice.leave_channel(state.guild_id)
  end
end
