defmodule MessageListener do
  @server MessageListener.Server

  def start_link() do
    GenServer.start_link(@server, nil, name: @server)
  end

  def listen(author_id, message_text, resolver, timeout \\ 30000) do
    GenServer.call(@server, {:listen, {author_id, message_text, resolver, timeout}})
  end

  def onmessage(author_id, message_text) do
    GenServer.call(@server, {:onmessage, {author_id, message_text}})
  end

  def remove(id) do
    GenServer.call(@server, {:remove, id})
  end
end
