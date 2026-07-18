-- Visual scenarios for the draft UI, discovered and run by the
-- BalatroMultiplayerDevTools shot harness. This file is INERT on its own:
-- the API mod never loads it, nothing here executes at boot, and it only
-- runs when a developer with the DevTools mod installed explicitly starts a
-- shot run (BMP_SHOT_SUITE=1 / DEVTOOLS.run_shot_suite()). It lives here --
-- next to dev/test_*.lua -- so the visual scenarios version WITH the code
-- they cover instead of drifting in the tools repo.
--
-- Contract: return function(H) -> list of scenario tables
--   { name, expect, region?, skip?, setup(done), teardown? }
-- H is the harness: H.start_draft(pool, schedule, first), H.find_tile(id),
-- H.find_ui(node, pred). See the DevTools README for the full shape.

return function(H)
	local PLAIN_POOL = { 'b_red', 'b_blue', 'b_yellow', 'b_green', 'b_black', 'b_magic', 'b_nebula', 'b_ghost', 'b_abandoned' }
	local TUPLE_POOL = {
		{ key = 'b_red', stake = 1 }, { key = 'b_red', stake = 5 }, { key = 'b_blue', stake = 3 },
		{ key = 'b_green', stake = 4 }, { key = 'b_black', stake = 1 }, { key = 'b_magic', stake = 3 },
		{ key = 'b_nebula', stake = 5 }, { key = 'b_ghost', stake = 1 }, { key = 'b_abandoned', stake = 4 },
	}
	-- actor = 1 matters: resolve_actor maps a step's actor through state.first,
	-- and a nil actor resolves as actor 2 -- without it every scene renders as
	-- the OPPONENT's turn.
	local BAN3 = { { actor = 1, action = 'ban', count = 3 } }

	-- The centered draft panel (no popups above it).
	local PANEL_REGION = { x = 0.22, y = 0.38, w = 0.56, h = 0.60 }
	-- Panel plus the airspace hover popups grow into.
	local HOVER_REGION = { x = 0.16, y = 0.04, w = 0.68, h = 0.94 }

	local function cocktail_missing()
		return not (G.P_CENTERS and G.P_CENTERS.b_mp_cocktail)
	end

	local function cocktail_pool()
		local pool = { unpack(TUPLE_POOL) }
		pool[3] = {
			key = 'b_mp_cocktail', stake = 3,
			cocktail = { 'b_green', 'b_black', 'b_mp_orange' },
			cocktail_name = 'Casjb',
		}
		return pool
	end

	return {
		{
			name = '01-ban-turn-plain',
			expect = "Draft overlay over the main menu: DECK BAN title, 'Your turn' status in green, 9 deck tiles in a row, 'Selected: 0/3' counter, greyed Confirm Ban, blue Random. No ERROR text anywhere.",
			region = PANEL_REGION,
			setup = function(done)
				H.start_draft(PLAIN_POOL, BAN3, 1)
				done()
			end,
		},
		{
			name = '02-selected-2of3',
			expect = "Two tiles (1st and 5th) raised with red 'Selected' tags; counter reads 'Selected: 2/3'; Confirm still greyed (needs exactly 3).",
			region = PANEL_REGION,
			setup = function(done)
				H.start_draft(PLAIN_POOL, BAN3, 1)
				local t1, t2 = H.find_tile('b_red'), H.find_tile('b_black')
				if t1 then t1:click() end
				if t2 then t2:click() end
				done()
			end,
		},
		{
			name = '03-random-armed',
			expect = "No tiles raised; counter reads '?/3'; Random button is RED reading 'Cancel Random'; Confirm is GREEN reading 'Confirm Random'.",
			region = PANEL_REGION,
			setup = function(done)
				H.start_draft(PLAIN_POOL, BAN3, 1)
				G.FUNCS.mpapi_ban_pick_random()
				done()
			end,
		},
		{
			name = '04-offturn-greyed',
			expect = "Status reads waiting/their-turn (not green); counter and BOTH buttons visible but greyed out; layout otherwise identical to scenario 01.",
			region = PANEL_REGION,
			setup = function(done)
				H.start_draft(PLAIN_POOL, BAN3, 2)
				done()
			end,
		},
		{
			name = '05-banned-tiles',
			expect = "Same board as 01 but the 2nd and 8th tiles are debuffed (darkened X overlay); they must not react to anything.",
			region = PANEL_REGION,
			setup = function(done)
				local lobby = H.start_draft(PLAIN_POOL, BAN3, 1)
				lobby._ban_pick.banned['b_blue'] = true
				lobby._ban_pick.banned['b_ghost'] = true
				MPAPI.BanPick.on_state(lobby, lobby._ban_pick)
				done()
			end,
		},
		{
			name = '06-tuple-hover-stake-column',
			expect = "Hover popup over the 7th tile: deck name + effects on the left, stake column on the right (stake name in its colour, description, 'Also applied' list). Popup fully on screen.",
			region = HOVER_REGION,
			setup = function(done)
				H.start_draft(TUPLE_POOL, BAN3, 1)
				local tile = H.find_tile('b_nebula@5')
				if tile then tile:hover() end
				done()
			end,
			teardown = function()
				local tile = H.find_tile('b_nebula@5')
				if tile then tile:stop_hover() end
			end,
		},
		{
			name = '07-cocktail-badge-hover',
			expect = "Badge pill above the tiles reads 'Casjb Cocktail: Green Deck + Black Deck + Orange Deck'; its hover shows the three decks SIDE BY SIDE with full effects, growing downward, fully on screen.",
			region = HOVER_REGION,
			skip = cocktail_missing,
			setup = function(done)
				H.start_draft(cocktail_pool(), BAN3, 1)
				local badge = H.find_ui(G.OVERLAY_MENU, function(n)
					return n.config.mp_comp_item ~= nil
				end)
				if badge then
					-- The rich hover is installed by the badge's per-frame init
					-- func; run it explicitly (idempotent) before hovering.
					G.FUNCS.mpapi_cocktail_badge_init(badge)
					badge:hover()
				end
				done()
			end,
		},
		{
			name = '08-cocktail-tile-hover-compact',
			expect = "Cocktail tile hover is COMPACT: 'Casjb Cocktail' title, 'rotating 3-deck mix' line, three deck NAMES only (no effect boxes), plus the stake column. Same footprint as a normal deck's hover.",
			region = HOVER_REGION,
			skip = cocktail_missing,
			setup = function(done)
				H.start_draft(cocktail_pool(), BAN3, 1)
				local tile = H.find_tile('b_mp_cocktail@3')
				if tile then tile:hover() end
				done()
			end,
		},
	}
end
