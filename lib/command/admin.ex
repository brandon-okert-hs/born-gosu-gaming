defmodule Admin do
  require Logger
  @api Application.get_env(:born_gosu_gaming, :discord_api)

  def run(%Command{discord_msg: m, command: "help"}), do: help(m.channel_id, m.author.id)
  def run(%Command{discord_msg: m, command: "setdaylightsavings", args: [region, enabled? | _]}), do: setdaylightsavings(m.channel_id, region, enabled?)
  def run(%Command{discord_msg: m, command: "daylightsavings"}), do: daylightsavings(m.channel_id)
  def run(%Command{discord_msg: m, command: "tryout", args: [user1, user2 | _]}), do: tryout(m.channel_id, m.guild_id, m.author.id, user1, user2)
  def run(%Command{discord_msg: m, command: "enableRolesListener", args: [mid, cid | rest]}), do: enableRolesListener(m.channel_id, m.guild_id, mid, cid, rest)
  def run(%Command{discord_msg: m, command: "disableRolesListener", args: [mid | _]}), do: disableRolesListener(m.channel_id, mid)
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

        - enableRolesListener <mid> <emoji1> <emoji2:role2> ...
            Reconfigures server role listeners on the given message id
            Each arg after the first is an emoji:role pair
            If the role is absent it is assumed to be the same as the emoji
            Use quotes if the role name has spaces
            eg: `!admin enableRolesListener 466648565415018507 462380629640740874 Zerg Protoss Terran Random`
            eg: `!admin enableRolesListener 466648570116702208 462380629640740874 Bronze Silver Gold Platinum Diamond Master`
            eg: `!admin enableRolesListener 487776565942288415 462380629640740874 Osu Coop "Pathofexile:Path of Exile"`
            eg: `!admin enableRolesListener 832456674 2346223 "newemoji:My New Role" "moar:Moarses"`

        - disableRolesListener <mid>
            Disabled an added role listener
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

  defp disableRolesListener(channel_id, target_mid) do
    case Integer.parse(target_mid) do
      {mid, ""} ->
        case Interaction.remove(mid) do
          :ok -> @api.create_message(channel_id, "Removed roles listener for #{mid}")
          {:error, _} -> @api.create_message(channel_id, "A role listener doesn't exist on #{mid}")
        end
      _ -> @api.create_message(channel_id, "The target message id needs to be an integer. You gave: `#{target_mid}`")
    end
  end

  defp enableRolesListener(channel_id, guild_id, target_mid, target_channel_id, raw_map) do
    guild = Nostrum.Cache.GuildCache.get!(guild_id)
    case Integer.parse(target_channel_id) do
      {cid, ""} ->
        case Integer.parse(target_mid) do
          {mid, ""} ->
            case @api.get_channel_message(cid, mid) do
              {:error, _} -> @api.create_message(channel_id, "A message with id #{mid} doesn't exist")
              {:ok, _} ->
                case parse_emoji_role_map(raw_map) do
                  s when is_binary(s) ->
                    @api.create_message(channel_id, "There were errors in your input:\n#{s}")
                  list ->
                    add_role_listener(list, mid, guild)
                    msg = list
                      |> Enum.map(fn {e, r} -> "Reacting with #{getmatchingemoji(e, guild)} will now apply role `#{r}`" end)
                      |> Enum.join("\n")
                    @api.create_message(channel_id, msg)
                end
            end
          _ -> @api.create_message(channel_id, "The target message id needs to be an integer. You gave: `#{target_mid}`")
        end
      _ -> @api.create_message(channel_id, "The target channel id needs to be an integer. You gave: `#{target_channel_id}`")
    end
  end

  defp parse_emoji_role_map(raw_args) do
    all = raw_args
      |> Enum.map(fn a -> parse_arg(a) end)
    correct = all
      |> Enum.filter(fn {l, _} -> l != :error end)
    incorrect = all
      |> Enum.filter(fn {l ,_} -> l == :error end)

    if Enum.count(incorrect) == 0 do
      correct
    else
      incorrect
        |> Enum.map(fn {_, e} -> e end)
        |> Enum.join("\n")
    end
  end

  defp parse_arg(raw_arg) do
    case String.split(raw_arg, ":") do
      [] -> {:error, "Your config option `#{raw_arg}` was somehow empty"}
      [role] -> {role, role}
      [emoji, role] -> {emoji, role}
      _ -> {:error, "Your config option `#{raw_arg}` had too many colons"}
    end
  end

  defp add_role_listener(roles, mid, guild) do
    reducer = fn (state, %{emoji: received_emoji, sender: sender_id, is_add: is_add}) ->
      matching_role = roles
        |> Enum.find(:none, fn {e, _} -> e == received_emoji end)

      case matching_role do
        {e, r} ->
          case DiscordQuery.role_by_name(r, guild) do
            :none ->
              with {:ok, dm} <- @api.create_dm(sender_id) do
                @api.create_message(dm.id, "The role `#{r}` for emoji `#{e}` doesn't exist. Please let an admin know.")
              end
            role ->
              if is_add do
                @api.add_guild_member_role(guild.id, sender_id, role.id)
              else
                @api.remove_guild_member_role(guild.id, sender_id, role.id)
              end
          end
        :none ->
          :noop
      end
      state
    end

    Interaction.create(%Interaction{
      name: "#{mid}:roleslistener",
      mid: mid,
      mstate: {},
      reducer: reducer,
      on_remove: nil,
    })
  end

  defp getmatchingemoji(emojiname, guild) do
    emoji = guild.emojis()
      |> Enum.find(emojiname, fn e -> e.name == emojiname end)

    case emoji do
      s when is_binary(s) ->
        s # built in emojis are just strings, like ":black_medium_square:"
      correct = %Nostrum.Struct.Emoji{} ->
        correct # guild.emojis() should only return these structs. But there's a bug where sometimes it returns maps instead
      %{animated: animated, id: id, managed: managed, name: name, require_colons: require_colons, roles: roles} ->
        %Nostrum.Struct.Emoji{animated: animated, id: id, managed: managed, name: name, require_colons: require_colons, roles: roles}
    end
  end
end
