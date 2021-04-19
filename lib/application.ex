defmodule Main do
  use Application

  def start_link do
    children = if Mix.env != :test do
      [
        {DiscordConsumer, name: DiscordConsumer},
        {Event.Persister, name: Event.Persister},
        %{id: Interaction, start: {Interaction, :start_link, []}},
        %{id: MessageListener, start: {MessageListener, :start_link, []}},
        %{id: Event.Reminder.Server, start: {Event.Reminder, :start_link, [Event.default_reminders()]}},
        %{id: Settings, start: {Settings, :start_link, []}},
      ]
    else
      # We don't startup the Nostrum application or the consumer or reminder service, but we still need the cache
      # Normally the app starts up the cache, so we do that here instead
      # Note that the cache will still be empty - tests need to populate it
      Nostrum.Application.setup_ets_tables()
      [
        {Event.Persister, name: Event.Persister}
      ]
    end

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def start(_type, _args) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    Main.start_link()
  end
end
