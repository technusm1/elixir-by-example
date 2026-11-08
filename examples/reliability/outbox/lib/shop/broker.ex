defmodule Shop.Broker do
  @moduledoc """
  A stand-in for a message broker (Kafka, RabbitMQ, SNS):
  another system, which keeps what it was sent even
  when the shop's node goes down. Here it's an
  append-only file.
  """

  @log "broker.log"

  def publish(id, topic, payload) do
    File.write!(@log, "#{id} #{topic} #{payload["item"]}\n", [:append])
  end

  def received do
    case File.read(@log) do
      {:ok, text} -> String.split(text, "\n", trim: true)
      {:error, :enoent} -> []
    end
  end
end
