-- Adds a REPORT PLAYER entry to the pause/options menu so a player can be
-- reported mid-run, where the in-run overlay HUD can't take clicks but the
-- ESC/options menu (a normal overlay_menu) can.

-- Forward declarations for helper functions
local get_other_players
local report_button
local picker_row
local cancel_button

-----------------------------
-- STATE VARIABLES
-----------------------------

-- The other-player list shown by the picker overlay when there's more than
-- one candidate. Set by mpapi_open_report_menu, read by the build fn.
local _picker_others = nil

-----------------------------
-- HELPERS
-----------------------------

-- Every lobby member except ourselves -- never report yourself.
get_other_players = function(lobby)
	local others = {}
	for _, p in ipairs(lobby:get_players()) do
		if p.id ~= lobby.player_id then
			others[#others + 1] = p
		end
	end
	return others
end

report_button = function()
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
		UIBox_button({ label = localize('b_report_player_cap'), button = 'mpapi_open_report_menu', minw = 5, minh = 0.7, scale = 0.4, colour = G.C.RED }),
	} }
end

-----------------------------
-- PICKER OVERLAY (multiple other players)
-----------------------------

picker_row = function(p)
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
		UIBox_button({
			label = { p.displayName or p.id },
			button = 'mpapi_report_pick_target',
			ref_table = { player_id = p.id, name = p.displayName or p.id },
			minw = 5, minh = 0.7, scale = 0.4, colour = G.C.RED,
		}),
	} }
end

cancel_button = function()
	return UIBox_button({ label = { localize('b_back') }, button = 'exit_overlay_menu', minh = 0.6, scale = 0.35, colour = G.C.UI.BACKGROUND_INACTIVE, focus_args = { nav = 'wide' } })
end

local create_UIBox_report_picker = function()
	if not _picker_others or #_picker_others == 0 then
		return G.FUNCS.exit_overlay_menu()
	end

	local nodes = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { text = localize('k_report_pick_title'), scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
		{ n = G.UIT.R, config = { minh = 0.15 } },
	}

	for _, p in ipairs(_picker_others) do
		nodes[#nodes + 1] = picker_row(p)
	end

	nodes[#nodes + 1] = { n = G.UIT.R, config = { minh = 0.15 } }
	nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = { cancel_button() } }

	local contents = {
		{ n = G.UIT.C, config = { align = 'cm', minw = 8, padding = 0.25, r = 0.1, colour = G.C.CLEAR }, nodes = nodes },
	}

	return create_UIBox_generic_options({ snap_back = true, contents = contents })
end

MPAPI.report_picker_overlay = MPAPI.ui_element(create_UIBox_report_picker)

-----------------------------
-- LOGIC FUNCTIONS
-----------------------------

G.FUNCS.mpapi_open_report_menu = function(e)
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return
	end

	local others = get_other_players(lobby)
	if #others == 1 then
		MPAPI.show_report_overlay({ player_id = others[1].id, name = others[1].displayName or others[1].id })
	elseif #others > 1 then
		_picker_others = others
		MPAPI.report_picker_overlay:as_overlay()
	end
end

G.FUNCS.mpapi_report_pick_target = function(e)
	local rt = e and e.config and e.config.ref_table
	if not rt or not rt.player_id then
		return
	end
	MPAPI.show_report_overlay({ player_id = rt.player_id, name = rt.name })
end

-----------------------------
-- PAUSE MENU HOOK
-----------------------------

-- Compose with whatever G.FUNCS.options already is (mod_registry/view.lua's pause
-- hook, itself layered over vanilla) -- never replace it. Build the options overlay
-- exactly as before, then splice our button into the freshly built UIBox. The pcall
-- keeps this defensive: if a mod's own options_builder produced a different shape,
-- the structural walk simply fails and that overlay is left untouched.
local before_options = G.FUNCS.options
G.FUNCS.options = function(e)
	before_options(e)

	local lobby = MPAPI.get_current_lobby()
	local others = lobby and get_other_players(lobby) or {}
	if #others == 0 then
		return
	end

	pcall(function()
		local contents_row = G.OVERLAY_MENU.UIRoot.children[1].children[1].children[1]
		G.OVERLAY_MENU:add_child(report_button(), contents_row)
	end)
end
