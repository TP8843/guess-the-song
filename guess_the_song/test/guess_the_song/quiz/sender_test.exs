defmodule GuessTheSong.Quiz.SenderTest do
  use ExUnit.Case, async: true

  alias GuessTheSong.Quiz.Sender

  # Reports each "sent" message back to the test process
  defp reporting_send(test_pid, delay_ms \\ 0) do
    fn channel_id, opts ->
      Process.sleep(delay_ms)
      send(test_pid, {:sent, channel_id, opts[:content]})
      {:ok, :message}
    end
  end

  test "sends messages in the order they were posted" do
    {:ok, sender} = Sender.start(self(), reporting_send(self()))

    for n <- 1..5, do: Sender.post(sender, 1, content: "message #{n}")

    # `receive` takes messages in arrival order, so this checks the order
    received =
      for _ <- 1..5 do
        receive do
          {:sent, 1, content} -> content
        after
          1_000 -> flunk("message not sent")
        end
      end

    assert received == Enum.map(1..5, &"message #{&1}")
  end

  test "sends queued messages after the owner stops, then exits" do
    test_pid = self()

    owner =
      spawn(fn ->
        receive do
          :go -> :ok
        end
      end)

    # Slow sends, so messages are still queued when the owner stops
    {:ok, sender} = Sender.start(owner, reporting_send(test_pid, 50))
    sender_ref = Process.monitor(sender)

    for n <- 1..3, do: Sender.post(sender, 1, content: "message #{n}")
    send(owner, :go)

    assert_receive {:sent, 1, "message 1"}, 1_000
    assert_receive {:sent, 1, "message 2"}, 1_000
    assert_receive {:sent, 1, "message 3"}, 1_000
    assert_receive {:DOWN, ^sender_ref, :process, ^sender, :normal}, 1_000
  end

  test "keeps going after a message fails" do
    test_pid = self()

    send_fun = fn channel_id, opts ->
      if opts[:content] == "bad", do: raise("Discord error")
      send(test_pid, {:sent, channel_id, opts[:content]})
    end

    {:ok, sender} = Sender.start(self(), send_fun)

    Sender.post(sender, 1, content: "bad")
    Sender.post(sender, 1, content: "good")
    assert_receive {:sent, 1, "good"}, 1_000
    assert Process.alive?(sender)
  end
end
