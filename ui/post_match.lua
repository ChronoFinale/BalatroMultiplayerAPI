-- Post-match moderation/social section: report other lobby players, and review +
-- appeal your own held (blocked) messages from this match. Two builders shared by
-- any gamemode mod's end screens (SPDRN win/lose today, PVP next) — lifted from
-- SPDRN 2026-07-12 because a second consumer appeared; contains no game logic.

-----------------------------
-- STATE VARIABLES
-----------------------------

-- Reactive element for the held-messages list: list_held is async, so the section
-- starts as "..." and swaps in-place once the callback lands (mirrors
-- ui/lobby/controls.lua's _mm_status_el pattern).
local _held_el = nil
local _held_data = nil -- nil = loading; {} or array of { message, band, createdAt } once fetched
local _held_error = false

-- One appeal per message, kept for the life of the mod session (not just this
-- screen) so re-showing a screen never lets the same message be appealed twice.
local _appealed = {}
local _appeal_pending = {}

-----------------------------
-- PLAYERS SECTION
-----------------------------

local function player_row(p)
	local name = p.displayName or p.id
	return {
		n = G.UIT.R,
		config = { align = 'cm', padding = 0.04 },
		nodes = {
			{ n = G.UIT.C, config = { align = 'cm', minw = 2.4, padding = 0.05 }, nodes = {
				{ n = G.UIT.T, config = { text = name, scale = 0.32, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
			} },
			{
				n = G.UIT.C,
				config = {
					ref_table = { player_id = p.id, name = name },
					align = 'cm', minw = 1.3, minh = 0.42, padding = 0.05, r = 0.08,
					colour = G.C.RED, hover = true, shadow = true, one_press = true,
					button = 'mpapi_post_match_report',
				},
				nodes = {
					{ n = G.UIT.T, config = { text = localize('b_report_cap'), scale = 0.28, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
				},
			},
		},
	}
end

-- Returns nil outside a lobby, or when there's nobody else to report (practice mode).
function MPAPI.build_post_match_players()
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return nil
	end

	local ok, players = pcall(function() return lobby:get_players() end)
	if not ok or not players then
		return nil
	end

	local rows = { {
		n = G.UIT.R,
		config = { align = 'cm', padding = 0.03 },
		nodes = { { n = G.UIT.T, config = { text = localize('k_post_match_players'), scale = 0.3, colour = G.C.UI.TEXT_INACTIVE, shadow = true } } },
	} }
	local other_count = 0
	for _, p in ipairs(players) do
		if p.id ~= lobby.player_id then
			other_count = other_count + 1
			rows[#rows + 1] = player_row(p)
		end
	end
	if other_count == 0 then
		return nil
	end

	return { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = rows }
end

G.FUNCS.mpapi_post_match_report = function(e)
	local ref = e and e.config and e.config.ref_table
	if not ref or not ref.player_id then
		return
	end
	local ok, err = pcall(MPAPI.show_report_overlay, { player_id = ref.player_id, name = ref.name })
	if not ok then
		MPAPI.sendWarnMessage('post_match report overlay error: ' .. tostring(err))
	end
end

-----------------------------
-- HELD / APPEAL SECTION
-----------------------------

local function held_row(h)
	local msg = h.message
	local action_node
	if _appealed[msg] then
		action_node = { n = G.UIT.C, config = { align = 'cm', minw = 1.3 }, nodes = {
			{ n = G.UIT.T, config = { text = localize('k_appeal_sent'), scale = 0.26, colour = G.C.GREEN, shadow = true } },
		} }
	else
		action_node = {
			n = G.UIT.C,
			config = {
				ref_table = { message = msg, band = h.band },
				align = 'cm', minw = 1.3, minh = 0.4, padding = 0.05, r = 0.08,
				colour = G.C.BLUE, hover = true, shadow = true, one_press = true,
				button = 'mpapi_post_match_appeal',
			},
			nodes = { { n = G.UIT.T, config = { text = localize('b_appeal_cap'), scale = 0.28, colour = G.C.UI.TEXT_LIGHT, shadow = true } } },
		}
	end

	return {
		n = G.UIT.R,
		config = { align = 'cm', padding = 0.03 },
		nodes = {
			{ n = G.UIT.C, config = { align = 'cm', minw = 3.2, padding = 0.05 }, nodes = {
				{ n = G.UIT.T, config = { text = MPAPI.truncate(tostring(msg), 40), scale = 0.28, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
			} },
			action_node,
		},
	}
end

-- Builds the held section's current contents: loading placeholder, an inline error,
-- nothing (0 held), or the header + one row per held message.
local function build_held_contents()
	if _held_error then
		return { nodes = { { n = G.UIT.R, config = { align = 'cm' }, nodes = {
			{ n = G.UIT.T, config = { text = localize('k_post_match_held_error'), scale = 0.26, colour = G.C.RED, shadow = true } },
		} } } }
	end
	if _held_data == nil then
		return { nodes = { { n = G.UIT.R, config = { align = 'cm' }, nodes = {
			{ n = G.UIT.T, config = { text = '...', scale = 0.3, colour = G.C.UI.TEXT_INACTIVE } },
		} } } }
	end
	if #_held_data == 0 then
		return { nodes = {} }
	end

	local nodes = { {
		n = G.UIT.R,
		config = { align = 'cm', padding = 0.03 },
		nodes = { { n = G.UIT.T, config = { text = localize('k_post_match_held'), scale = 0.3, colour = G.C.UI.TEXT_INACTIVE, shadow = true } } },
	} }
	for _, h in ipairs(_held_data) do
		nodes[#nodes + 1] = held_row(h)
	end
	return { nodes = nodes }
end

local function fetch_held(lobby)
	_held_data = nil
	_held_error = false
	local ok, err = pcall(MPAPI._internal.list_held, lobby.code, function(err2, data)
		if err2 then
			_held_error = true
			MPAPI.sendWarnMessage('list_held error: ' .. tostring(err2))
		else
			_held_data = (data and data.held) or {}
		end
		if _held_el then
			_held_el:update()
		end
	end)
	if not ok then
		_held_error = true
		MPAPI.sendWarnMessage('list_held call error: ' .. tostring(err))
	end
end

-- Returns nil outside a lobby. Always renders the reactive box once in a lobby --
-- it starts as "..." and collapses to nothing on 0 held messages, so callers don't
-- need to special-case the async result.
function MPAPI.build_post_match_held()
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return nil
	end

	_held_el = _held_el or MPAPI.ui_element(build_held_contents)
	fetch_held(lobby)

	return { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = { _held_el.node } }
end

G.FUNCS.mpapi_post_match_appeal = function(e)
	local ref = e and e.config and e.config.ref_table
	if not ref or not ref.message then
		return
	end
	local msg = ref.message
	if _appealed[msg] or _appeal_pending[msg] then
		return
	end

	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return
	end

	_appeal_pending[msg] = true
	local ok, err = pcall(MPAPI._internal.appeal_message, lobby.code, msg, ref.band, function(err2, _)
		_appeal_pending[msg] = nil
		if err2 then
			MPAPI.chat.addMessage('[!] ' .. tostring(err2), { 1, 1, 0 })
			return
		end
		_appealed[msg] = true
		if _held_el then
			_held_el:update()
		end
	end)
	if not ok then
		_appeal_pending[msg] = nil
		MPAPI.sendWarnMessage('appeal_message call error: ' .. tostring(err))
	end
end
