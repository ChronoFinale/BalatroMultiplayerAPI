-- Forward declarations for helper functions
local category_button
local mute_button
local cancel_button

-----------------------------
-- STATE VARIABLES
-----------------------------

-- The player currently targeted by the overlay: { player_id, name }. Set by
-- MPAPI.show_report_overlay, read by the build fn and the button handlers.
local _target = nil
local _submitting = false

-----------------------------
-- UI FUNCTIONS
-----------------------------

local create_UIBox_report_overlay = function()
	if not _target then
		return G.FUNCS.exit_overlay_menu()
	end

	local name = _target.name or _target.player_id

	local contents = {
		{
			n = G.UIT.C,
			config = { align = 'cm', minw = 8, padding = 0.25, r = 0.1, colour = G.C.CLEAR },
			nodes = {
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.1 },
					nodes = {
						{ n = G.UIT.T, config = { text = localize('k_report_title') .. ' ' .. name, scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
					},
				},
				{ n = G.UIT.R, config = { minh = 0.15 } },
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.06 },
					nodes = {
						category_button('harassment', 'b_report_harassment'),
						category_button('hate', 'b_report_hate'),
					},
				},
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.06 },
					nodes = {
						category_button('threats', 'b_report_threats'),
						category_button('spam', 'b_report_spam'),
					},
				},
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.06 },
					nodes = {
						category_button('other', 'b_report_other'),
					},
				},
				{ n = G.UIT.R, config = { minh = 0.15 } },
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.06 },
					nodes = { mute_button() },
				},
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.06 },
					nodes = { cancel_button() },
				},
			},
		},
	}

	return create_UIBox_generic_options({ snap_back = true, contents = contents })
end

category_button = function(category, label_key)
	local config = {
		align = 'cm', padding = 0.1, minw = 3.6, minh = 0.55, r = 0.1,
		colour = _submitting and G.C.UI.BACKGROUND_INACTIVE or G.C.RED,
		shadow = true,
	}
	if not _submitting then
		config.hover = true
		config.one_press = true
		config.ref_table = { category = category }
		config.button = 'mpapi_report_submit'
	end

	local text_colour = _submitting and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT
	return { n = G.UIT.C, config = config, nodes = {
		{ n = G.UIT.T, config = { text = localize(label_key), scale = 0.38, colour = text_colour, shadow = true } },
	} }
end

mute_button = function()
	local config = {
		align = 'cm', padding = 0.1, minw = 3.6, minh = 0.55, r = 0.1,
		colour = _submitting and G.C.UI.BACKGROUND_INACTIVE or G.C.BLUE,
		shadow = true,
	}
	if not _submitting then
		config.hover = true
		config.one_press = true
		config.button = 'mpapi_report_mute'
	end

	local text_colour = _submitting and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT
	return { n = G.UIT.C, config = config, nodes = {
		{ n = G.UIT.T, config = { text = localize('b_mute_player'), scale = 0.38, colour = text_colour, shadow = true } },
	} }
end

cancel_button = function()
	return UIBox_button({ label = { localize('b_back') }, button = 'exit_overlay_menu', minh = 0.6, scale = 0.35, colour = G.C.UI.BACKGROUND_INACTIVE, focus_args = { nav = 'wide' } })
end

-----------------------------
-- LOGIC FUNCTIONS
-----------------------------

G.FUNCS.mpapi_report_submit = function(e)
	if _submitting or not _target then return end
	local category = e and e.config and e.config.ref_table and e.config.ref_table.category
	if not category then return end

	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return G.FUNCS.exit_overlay_menu()
	end

	local player_id, name = _target.player_id, _target.name

	_submitting = true
	if MPAPI.report_overlay then MPAPI.report_overlay:update() end

	MPAPI._internal.report_player(lobby.code, player_id, category, nil, function(err, _)
		_submitting = false
		G.FUNCS.exit_overlay_menu()
		if err then
			MPAPI.chat.addMessage('[!] ' .. tostring(err), { 1, 1, 0 })
		else
			MPAPI.chat.addMessage(localize('k_chat_report_sent') .. ' ' .. name, { 1, 1, 0 })
		end
	end)
end

G.FUNCS.mpapi_report_mute = function(e)
	if not _target then return end
	MPAPI.chat.mute_player(_target.player_id, _target.name)
	G.FUNCS.exit_overlay_menu()
end

-----------------------------
-- GLOBAL UI ELEMENT
-----------------------------

MPAPI.report_overlay = MPAPI.ui_element(create_UIBox_report_overlay)

-----------------------------
-- API FUNCTIONS
-----------------------------

-- Opts: { player_id = <string>, name = <string> }. Silently no-ops outside a
-- lobby -- there is nobody to report/mute without a live lobby context.
function MPAPI.show_report_overlay(opts)
	if not MPAPI.get_current_lobby() then
		return
	end

	_target = opts
	_submitting = false
	MPAPI.report_overlay:as_overlay()
end
