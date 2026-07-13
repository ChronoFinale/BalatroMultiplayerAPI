-- Overlay shown when the player tries to start any run (New Run, Continue,
-- Challenge, restart) while a matchmaking search is active. The gate itself
-- lives in api/matchmaking/run_guard.lua, which opens this in place of letting
-- G.FUNCS.start_run proceed.
--
-- Two ways out, both always available (never soft-locks, even if the search
-- ends while this is open -- neither branch reads search state):
--   Leave Queue  -- leaves every active handle, then dismisses back to the
--                   menu (does not retry the run; click Play again for that).
--   Stay Queued  -- the overlay's own back button (and Esc); just dismisses.
local create_UIBox_queue_guard_overlay = function()
	local contents = {
		{
			n = G.UIT.C,
			config = { align = 'cm', minw = 6, padding = 0.25, r = 0.1, colour = G.C.CLEAR },
			nodes = {
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.1 },
					nodes = {
						{ n = G.UIT.T, config = { text = localize('k_queue_guard_title'), scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
					},
				},
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.06 },
					nodes = {
						{ n = G.UIT.T, config = { text = localize('k_queue_guard_desc'), scale = 0.3, colour = G.C.UI.TEXT_LIGHT } },
					},
				},
				{ n = G.UIT.R, config = { minh = 0.15 } },
				{
					n = G.UIT.R,
					config = { align = 'cm' },
					nodes = {
						{
							n = G.UIT.C,
							config = {
								align = 'cm', padding = 0.1, minw = 4, minh = 0.7,
								r = 0.1, hover = true, colour = G.C.RED, shadow = true,
								button = 'mpapi_queue_guard_leave',
							},
							nodes = {
								{ n = G.UIT.T, config = { text = localize('b_queue_guard_leave'), scale = 0.38, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
							},
						},
					},
				},
			},
		},
	}

	return create_UIBox_generic_options({
		snap_back = true,
		back_colour = G.C.GREEN,
		back_label = localize('b_queue_guard_stay'),
		contents = contents,
	})
end

-----------------------------
-- LOGIC FUNCTIONS
-----------------------------

-- Leave every active matchmaking handle (the same per-handle path a
-- consumer mod's own Cancel-Search button uses: handle:leave() marks it left,
-- removes it from mm.handles, and tells the server), then dismiss back to the
-- menu. Copy the list first -- handle:leave() mutates mm.handles in place via
-- mm.remove_handle, which would break live iteration.
G.FUNCS.mpapi_queue_guard_leave = function(e)
	local mm = MPAPI._internal.mm
	local handles = MPAPI.shallow_copy(mm.handles or {})
	for _, h in ipairs(handles) do
		h:leave()
	end
	G.FUNCS.exit_overlay_menu()
end

-----------------------------
-- GLOBAL UI ELEMENT
-----------------------------

MPAPI.queue_guard_overlay = MPAPI.ui_element(create_UIBox_queue_guard_overlay)
