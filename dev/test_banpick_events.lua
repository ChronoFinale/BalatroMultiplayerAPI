--[[
  Ban-pick on_action_applied hook test.

  The engine fires config.on_action_applied(seq, player_id, action, key, stake)
  on the HOST after every applied action (bans and the pick). Consumers forward
  these to the server's draft-event stash; seq is the server-side dedup key, so
  it must increment 0,1,2,... per applied action. Consumer errors in the hook
  must never break a live draft (pcall).

  Run from the repo root:
    luajit dev/test_banpick_events.lua
]]

-- ── Stubs ───────────────────────────────────────────────────────────────────
MPAPI = { sendWarnMessage = function() end }
G = {
	FUNCS = {},
	C = { GREEN = 'green', MULT = 'mult', BLUE = 'blue', WHITE = 'white', BLACK = 'black', CLEAR = 'clear', UI = { BACKGROUND_INACTIVE = 'inactive', TEXT_LIGHT = 'light' } },
}

dofile('api/ban_pick.lua')
local BP = MPAPI.BanPick

MPAPI.ActionTypes = {}
local LOBBY = {
	is_host = true,
	player_id = 'host',
	get_players = function(_self)
		return { { id = 'host' }, { id = 'guest' } }
	end,
}
MPAPI.get_current_lobby = function()
	return LOBBY
end

-- Tuple pool: {key, stake} items, matching a server-issued pool's shape.
local POOL = {
	{ key = 'b_red', stake = 1 },
	{ key = 'b_blue', stake = 4 },
	{ key = 'b_yellow', stake = 8 },
	{ key = 'b_green', stake = 1 },
}

local events = {}
local function start_draft(hook)
	events = {}
	BP.start(LOBBY, {
		build_pool = function()
			local copy = {}
			for i, item in ipairs(POOL) do copy[i] = item end
			return copy
		end,
		schedule = {
			{ actor = 1, action = 'ban', count = 2 },
			{ actor = 2, action = 'ban', count = 1 },
			{ actor = 1, action = 'pick', count = 1 },
		},
		state_action = 's',
		ban_action = 'b',
		on_refresh = function() end,
		on_action_applied = hook or function(seq, player_id, action, key, stake)
			events[#events + 1] = { seq = seq, player = player_id, action = action, key = key, stake = stake }
		end,
	}, function() end)
	LOBBY._ban_pick.first = 1 -- deterministic: actor 1 = host
end

-- ── Harness ────────────────────────────────────────────────────────────────
local failures = 0
local function check(cond, msg)
	if cond then print('PASS: ' .. msg) else failures = failures + 1; print('FAIL: ' .. msg) end
end

print()
print('-- hook fires per applied action with incrementing seq --')
start_draft()
check(BP.apply_ban(LOBBY, 'host', 'b_red') == true, 'host ban 1 applies')
check(BP.apply_ban(LOBBY, 'host', 'b_blue') == true, 'host ban 2 applies')
check(BP.apply_ban(LOBBY, 'guest', 'b_yellow') == true, 'guest ban applies')
check(BP.apply_ban(LOBBY, 'host', 'b_green') == true, 'host pick applies')
check(#events == 4, 'one event per applied action')
check(events[1].seq == 0 and events[2].seq == 1 and events[3].seq == 2 and events[4].seq == 3,
	'seq increments 0,1,2,3')
check(events[1].action == 'ban' and events[4].action == 'pick', 'actions labelled ban/pick')
check(events[3].player == 'guest', 'guest actions carry the guest id')
check(events[1].key == 'b_red' and events[1].stake == 1, 'tuple items carry key + stake')
check(events[4].key == 'b_green' and events[4].stake == 1, 'the pick carries key + stake')

print()
print('-- rejected actions fire nothing --')
start_draft()
check(BP.apply_ban(LOBBY, 'guest', 'b_red') == false, 'off-turn ban rejected')
check(BP.apply_ban(LOBBY, 'host', 'b_nope') == false, 'unknown key rejected')
check(#events == 0, 'no events for rejected actions')

print()
print('-- a throwing hook never breaks the draft --')
start_draft(function() error('consumer bug') end)
check(BP.apply_ban(LOBBY, 'host', 'b_red') == true, 'action still applies when the hook throws')
check(LOBBY._ban_pick.banned['b_red'] == true, 'state still mutated')

print()
print('-- no hook configured: draft runs as before --')
events = {}
BP.start(LOBBY, {
	build_pool = function() return { 'b_red', 'b_blue' } end,
	schedule = { { actor = 1, action = 'ban', count = 1 } },
	state_action = 's',
	ban_action = 'b',
	on_refresh = function() end,
}, function() end)
LOBBY._ban_pick.first = 1
check(BP.apply_ban(LOBBY, 'host', 'b_red') == true, 'plain-key pool applies without a hook')
check(#events == 0, 'nothing fired')

-- ── Summary ─────────────────────────────────────────────────────────────────
print()
if failures == 0 then
	print('ALL TESTS PASSED')
	os.exit(0)
else
	print(failures .. ' TEST(S) FAILED')
	os.exit(1)
end
