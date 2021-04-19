defmodule Admin do
  require Logger
  @api Application.get_env(:born_gosu_gaming, :discord_api)

  def run(%Command{discord_msg: m, command: "help"}), do: help(m.channel_id, m.author.id)
  def run(%Command{discord_msg: m, command: "setdaylightsavings", args: [region, enabled? | _]}), do: setdaylightsavings(m.channel_id, region, enabled?)
  def run(%Command{discord_msg: m, command: "daylightsavings"}), do: daylightsavings(m.channel_id)
  def run(%Command{discord_msg: m, command: "tryout", args: [user1, user2 | _]}), do: tryout(m.channel_id, m.guild_id, m.author.id, user1, user2)
  def run(%Command{discord_msg: m, command: command, args: args}), do: unknown(m.channel_id, command, args, m.author.username, m.author.discriminator)

  defp unknown(channel_id, command, args, username, discriminator) do
    cmd = "`!admin #{command} #{Enum.join(args, ", ")}` from #{username}\##{discriminator}"
    @api.create_message(channel_id, "Apologies, but I'm not sure what to do with this admin command: #{cmd}")
  end

  defp help(channel_id, author_id) do
    @api.create_message(channel_id, "I'll dm you")
    with {:ok, dm} <- @api.create_dm(author_id) do
      @api.create_message(dm.id, String.trim("""
      Available commands:
        - daylightsavings
            Displays what the settings for daylight savings are
            eg: '!admin daylightsavings'
        
        - setdaylightsavings <eu|na> <yes|no>
            Toggles the default output formats between Daylight Savings and Summer
            times.
            eg: '!admin setdaylightsavings na yes'
            eg: '!admin setdaylightsavings eu no'
      """))
    end
  end

  defp daylightsavings(channel_id) do
    settings = Settings.get_output_timezones()
    if Map.has_key?(settings, :EDT), do: @api.create_message(channel_id, "For NA, daylight savings is active")
    if Map.has_key?(settings, :EST), do: @api.create_message(channel_id, "For NA, daylight savings is not active")
    if Map.has_key?(settings, :CEST), do: @api.create_message(channel_id, "For EU, daylight savings is active")
    if Map.has_key?(settings, :CET), do: @api.create_message(channel_id, "For EU, daylight savings is not active")
  end

  defp setdaylightsavings(channel_id, region, enabled?) do
    case {region, enabled?} do
      {"eu", "yes"} ->
        Settings.set_daylight_savings(true, :eu)
        @api.create_message(channel_id, "Alright I've set output to use daylight savings for europe")
      {"eu", "no"} ->
        Settings.set_daylight_savings(false, :eu)
        @api.create_message(channel_id, "Alright I've set output to not use daylight savings for europe")
      {"na", "yes"} ->
        Settings.set_daylight_savings(true, :na)
        @api.create_message(channel_id, "Alright I've set output to use daylight savings for north america")
      {"na", "no"} ->
        Settings.set_daylight_savings(false, :na)
        @api.create_message(channel_id, "Alright I've set output to not use daylight savings for north america")
      _ ->
        @api.create_message(channel_id, "Invalid region or state. Try `!events setdaylightsavings eu yes` or `!events setdaylightsavings na no`")
    end
  end

  defp tryout(channel_id, guild_id, author_id, raw_mentee, raw_mentor) when is_binary(raw_mentor) and is_binary(raw_mentee) do
    users = @api.list_guild_members(guild_id, limit: 1000)
    case users do
      {:error, e} ->
        @api.create_message(channel_id, "Discord failed to fetch users. Try again?")
        Logger.error("Error when searching discord for users with !admin tryout: #{e}")
      {:ok, members_raw} ->
        with guild <- Nostrum.Cache.GuildCache.get!(guild_id) do
          members = members_raw
            |> Enum.filter(fn m -> m.user.bot == nil end)
          mentors = members
            |> Enum.filter(fn m -> DiscordQuery.member_has_role?(m, "Mentors", guild) end)
            |> Enum.filter(fn m -> String.contains?(String.downcase(m.user.username), String.downcase(raw_mentor)) end)
          non_members = members
            |> Enum.filter(fn m -> DiscordQuery.member_has_role?(m, "Non-Born Gosu", guild) end)
            |> Enum.filter(fn m -> String.contains?(String.downcase(m.user.username), String.downcase(raw_mentee)) end)
          author = @api.get_guild_member!(guild.id, author_id)

          tryout_response(guild_id, channel_id, author, mentors, non_members, raw_mentor, raw_mentee)
        end
    end
  end

  defp tryout_response(_, channel_id, _, [], [], raw_mentor, raw_mentee) do
    @api.create_message(channel_id, "No mentors matching '#{raw_mentor}' found, and no non-members matching '#{raw_mentee}' found")
  end
  defp tryout_response(_, channel_id, _, [], mentees, raw_mentor, _) do
    @api.create_message(channel_id, "No mentors matching '#{raw_mentor}' found, but found matching mentees: #{users_to_csv(mentees)}")
  end
  defp tryout_response(_, channel_id, _, mentors, [], _, raw_mentee) do
    @api.create_message(channel_id, "No non members matching '#{raw_mentee}' found, but found matching mentors: #{users_to_csv(mentors)}")
  end
  defp tryout_response(_, channel_id, author, mentors, mentees, _, _) do
    matches = (for m <- mentors, n <- mentees, do: {m, n})
      |> Enum.with_index()
      |> Enum.map(fn {{m, n}, i} -> {m, n, i} end)

    @api.create_message(channel_id, "Found #{Enum.count(matches)} possible parings. I'll list them 10 at a time, and you just type eg `!admin choose 16` to apply that pairing. I'll wait 30 seconds for your choice.")

    matches
      |> Enum.map(fn {m, n, i} -> MessageListener.listen(author.user.id, "!admin choose #{i+1}", fn () ->
        @api.create_message(channel_id, "Alright I'll make #{n} a mentee of #{m}...\n(TO BE IMPLEMENTED)")
      end, 30000) end)

    matches
      |> Enum.map(fn {m, n, i} -> "#{i+1}: make #{n.user} a mentee of #{m.user.username}" end)
      |> Enum.chunk_every(10)
      |> Enum.map(fn chunk -> Enum.join(chunk, "\n") end)
      |> Enum.map(fn block ->
        @api.create_message(channel_id, block)
        :timer.sleep(2000) end)
  end

  defp users_to_csv(users) do
    users
      |> Enum.map(fn m -> m.user.username end)
      |> Enum.join(", ")
  end
end
