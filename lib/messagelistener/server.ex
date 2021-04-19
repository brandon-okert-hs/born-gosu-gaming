defmodule MessageListener.Server do
  use GenServer
  require Logger

  def init(_) do
    {:ok, %{}}
  end

  def handle_call({:listen, {author_id, message_text, resolver, timeout}}, _from, listeners) do
    id = "#{author_id}-#{message_text}"
    Task.start(fn ->
      :timer.sleep(timeout)
      Logger.info "Removing listener #{id}"
      MessageListener.remove(id)
    end)
    {:reply, {:ok, id}, Map.put(listeners, id, {author_id, message_text, resolver, timeout})}
  end

  def handle_call({:remove, id}, _from, listeners) do
    case listeners do
      %{^id => _} ->
        {:reply, :ok, Map.delete(listeners, id)}
      _ ->
        {:reply, {:error, "That listener doesn't exist"}, listeners}
    end
  end

  def handle_call({:onmessage, {author_id, message_text}}, _from, listeners) do
    id = "#{author_id}-#{message_text}"
    case listeners do
      %{^id => {_, _, resolver, _}} ->
        resolver.()
        {:reply, :found, Map.delete(listeners, id)}
      _ ->
        {:reply, :notfound, listeners}
    end
  end
end
