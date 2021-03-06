
local commands = bot.commands

local animeChoice = 1
local function animeToEmbed(data, choice)
	local _msg = {}

	local animes = data.anime:numChildren()
	local choice = math.clamp(choice, 1, animes) or 1
	local anime
	local multiple = data.anime.entry[2]
	if multiple then
		table.sort(data.anime.entry, function(a, b)
			return a.score:value() > b.score:value()
		end)
		anime = data.anime.entry[choice]
	else
		anime = data.anime.entry
	end

	-- Prepare for displaying data
	local title = anime.title:value()
	local id = anime.id:value()
	local _type = anime.type:value()
	local score = anime.score:value()
	local image = anime.image:value()
	local synopsis = anime.synopsis:value()
	if synopsis then
		synopsis = synopsis:gsub("<br%s?/>", "")
		synopsis = xml:FromXmlString(synopsis)
		synopsis = synopsis:gsub("&mdash;", "—")
		synopsis = synopsis:gsub("%[%w%]([%w%s]*)%[/%w%]", "%1") -- remove bbcode
		if #synopsis > 512 then
			synopsis = synopsis:sub(1, 512)
			synopsis = synopsis .. "[...]"
		end
		synopsis = "**Synopsis: **\n" .. synopsis
		local english = anime.english:value()
		if english then
			synopsis = "**English name:** " .. english .. "\n\n" .. synopsis
		end
	end
	local status = anime.status:value()
	local episodes = anime.episodes:value()
	episodes = (status:lower():match("airing") and tonumber(episodes) == 0) and "?" or episodes
	local startDate, endDate = anime.start_date:value(), anime.end_date:value()
	local isAiring = endDate == "0000-00-00"
	local airTime = isAiring and "Airing since " .. startDate or "Aired from " .. startDate .. " to " .. endDate

	_msg.embed = {
		title = title,
		description = synopsis,
		url = "http://myanimelist.net/anime/" .. id,
		fields = {
			{
				name = "Episodes - Status",
				value = episodes .. " - " .. status,
				inline = true
			},
			{
				name = "Type",
				value = _type,
				inline = true
			},
			{
				name = "Score",
				value = score,
				inline = true
			}
		},
		thumbnail = {
			url = image
		},
		color = 0xFF7FFF,
		footer = {
			icon_url = client.user.avatar_url,
			text = airTime .. " - MyAnimeList API"
		}
	}
	if multiple then
		_msg.embed.footer.text = "Page " .. choice .. "/" .. animes .. " - " .. _msg.embed.footer.text
	end

	return _msg, multiple
end
commands[{"anime", "mal"}] = {
	callback = function(msg, line)
		if not config.mal then return false, "No MyAnimeList credentials provided." end
		if not xml then return false, "No XML module." end

		local query = line
		if not query then return false, "No search query provided." end

		local get = querystring.stringify({
			q = query
		})

		local url = "https://myanimelist.net/api/anime/search.xml?" .. get
		local options = http.parseUrl(url)
		if not options.headers then options.headers = {} end
		options.headers["Authorization"] = "Basic " .. config.mal -- base64.decode(config.mal)
		local found = false
		local body = ""
		local req = https.get(options, function(res)
			res:on("data", function(chunk)
				body = body .. chunk
			end)
			res:on("end", function()
				local data = xml:ParseXmlText(body)
				if data.anime then
					animeChoice = 1
					local _msg, multiple = animeToEmbed(data, animeChoice)
					found = true
					coroutine.wrap(function()
						local resultsMsg = msg.channel:send(_msg) -- well this is ass.
						if multiple then
							paging.init(resultsMsg, msg, data, function(page, fwd)
								local oldChoice = animeChoice
								animeChoice = math.clamp(animeChoice + (fwd and 1 or -1), 1, page.data.anime:numChildren())
								if oldChoice == animeChoice then return end

								local _msg = animeToEmbed(page.data, animeChoice)
								page.message:setEmbed(_msg.embed)
							end)
						end
					end)()
				else
					cmdError(body, "MyAnimeList API")
				end
			end)
		end)

		timer.setTimeout(5000, function()
			if not found then
				cmdError("No anime found.", "MyAnimeList API")
			end
		end)
	end,
	help = {
		text = "Provides condensed information about an anime.\n*Makes uses of reactions to create a page system that the caller can use to browse through multiple results!*",
		usage = "`{prefix}{cmd} <anime name>`",
		example = "`{prefix}{cmd} Charlotte`"
	},
	category = "Utility"
}

commands[{"translate", "tr", "тр"}] = {
	callback = function(msg, line, text, lang)
		if not config.yandex then return false, "No Yandex API key provided." end

		lang = lang and lang:lower() or "en"
		local get = querystring.stringify({
			key = config.yandex,
			lang = lang,
			text = text
		})

		local _msg = {}
		local url = "https://translate.yandex.net/api/v1.5/tr.json/translate?" .. get
		local req = https.get(url, function(res)
			res:on("data", function(body)
				local data = json.decode(body)
				if data.code == 200 then
					_msg.embed = {
						title = "Translation to `" .. data.lang .. "`",
						description = data.text[1] or "No translation available",
						footer = {
							text = "Yandex Translate API"
						},
						color = 0x00FFC0
					}
					coroutine.wrap(function()
						msg.channel:send(_msg) -- well this is ass.
					end)()
				else
					cmdError(data.message, "Yandex Translate API - code " .. data.code .. " - lang " .. lang)
				end
			end)
		end)
	end,
	help = {
		text = "Translate stuff.",
		example = '`{prefix}{cmd} "I like apples",en-fr` will translate the sentence "I like apples" from English to French .'
	},
	category = "Utility"
}

local function validSteamID(sid)
	return sid:upper():trim():match("^STEAM_0:%d:%d+$")
end
local function th(num)
	local num = tonumber(tostring(num):match("(%d$)"))
	if num == 1 then
		return "st"
	elseif num == 2 then
		return "nd"
	elseif num == 3 then
		return "rd"
	else
		return "th"
	end
end
local function sid64ToSid(sid64)
	local sid64 = tonumber(sid64:sub(2))
	local universe = sid64 % 2 == 0 and 0 or 1
	local id = math.abs(6561197960265728 - sid64 - universe) * 0.5
	local sid = "STEAM_0:" .. universe .. ":" .. (universe == 1 and id - 1 or id)
	return sid
end
local function sidToSid64(sid)
	local universe, id = sid:match("STEAM_0:(%d):(%d+)")
	return "7" .. ("%.0f"):format(math.abs(6561197960265728 + id * 2 + universe))
end
local onlineStates = {
	[0] = "Offline",
	[1] = "Online",
	[2] = "Busy",
	[3] = "Away",
	[4] = "Snooze",
	[5] = "Looking to Trade",
	[6] = "Looking to Play"
}
local steamIcon = "https://re-dream.org/media/steam-white-transparent.png"
local function sendSteamIDResult(msg, url)
	local get = querystring.stringify({
		key = config.steam,
		steamids = url
	})
	local options = http.parseUrl("http://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?" .. get)
	local body = ""
	local req = http.get(options, function(res)
		res:on("data", function(chunk)
			body = body .. chunk
		end)
		res:on("end", function()
			local data = json.decode(body)
			if data and data.response then
				data = data.response
				if data.players and table.count(data.players) > 0 then
					data = table.getfirstvalue(data.players)
				else
					cmdError("No players found.", "Steam Web API", steamIcon)
					return
				end
			else
				cmdError("No players found.", "Steam Web API", steamIcon)
				return
			end

			local onlineState = onlineStates[data.personastate] or "??"
			if data.personastate == 0 then
				local day = os.date("%d", data.lastlogoff)
				onlineState = onlineState .. "\nLast online: " .. os.date("%A %%s, %B %Y %X", data.lastlogoff):format(tostring(day) .. th(day))
			end
			local _msg = {
				embed = {
					title = data.personaname,
					url = data.profileurl,
					description = onlineState,
					thumbnail = {
						url = data.avatarfull
					},
					fields = {},
					footer = {
						icon_url = steamIcon,
						text = sid64ToSid(data.steamid) .. " / " .. data.steamid
					},
					color = data.personastate ~= 0 and (data.gameid and 0x7FFF40 or 0x50ACFF),
				}
			}
			if data.gameid then
				_msg.embed.fields[#_msg.embed.fields + 1] = {
					name = "Playing",
					value = (data.gameextrainfo or "No game name??") .. " (" .. data.gameid .. ")"
				}
				if data.gameserverip and data.gameserverip ~= "0.0.0.0:0" then
					_msg.embed.fields[#_msg.embed.fields + 1] = {
						name = "Join",
						value = "steam://connect/" .. data.gameserverip
					}
				end
			end
			if data.timecreated then
				local day = os.date("%d", data.timecreated)
				local timeCreated = os.date("%A %%s, %B %Y %X", data.timecreated):format(tostring(day) .. th(day))

				_msg.embed.fields[#_msg.embed.fields + 1] = {
					name = "Account created",
					value = timeCreated
				}
			end

			coroutine.wrap(function()
				msg.channel:send(_msg)
			end)()
		end)
	end)
end
commands[{"steam", "steamid", "sid"}] = {
	callback = function(msg, line)
		if not config.steam then errorMsg(msg.channel, "No Steam Web API key provided.") return end

		local query = line
		if not query then errorMsg(msg.channel, "No search query provided.") return end

		if validSteamID(line) then
			local sid64 = sidToSid64(line:upper():trim())
			local url = sid64
			return sendSteamIDResult(msg, url)
		elseif line:match("^https?://steamcommunity.com/id/%w*/?") or line:match("^https?://steamcommunity.com/profiles/%d*/?") then
			local ret = {}
			local url = line:gsub("/*$", ""):gsub("^http://", "https://") .. "/?xml=1"
			local options = http.parseUrl(url)
			local body = ""
			local req = https.get(options, function(res)
				res:on("data", function(chunk)
					body = body .. chunk
				end)
				res:on("end", function()
					url = body:match("<steamID64>(.*)</steamID64>")
					ret = { sendSteamIDResult(msg, url) }
				end)
			end)
			return unpack(ret)
		elseif type(tonumber(line)) == "number" then
			return sendSteamIDResult(msg, line)
		else
			local ret = {}
			local get = querystring.urlencode(line)
			local url = "https://steamcommunity.com/id/" .. get .. "/?xml=1"
			local options = http.parseUrl(url)
			local body = ""
			local req = https.get(options, function(res)
				res:on("data", function(chunk)
					body = body .. chunk
				end)
				res:on("end", function()
					url = body:match("<steamID64>(.*)</steamID64>")
					ret = { sendSteamIDResult(msg, url) }
				end)
			end)
			return unpack(ret)
		end
	end,
	help = {
		text = "Looks for a [Steam](http://steamcommunity.com) profile using a custom URL name, SteamID, SteamID64, or URL and returns basic information.",
		example = [[`{prefix}{cmd} tenrys`
`{prefix}{cmd} STEAM_0:1:32476157`
`{prefix}{cmd} 76561198025218043`
`{prefix}{cmd} https://steamcommunity.com/id/tenrys`]]
	},
	category = "Utility"
}

