-- Standalone regression test for the matchmaking queue guard: blocking
-- singleplayer run-start (api/matchmaking/queue_guard.lua) and blocking lobby
-- create/join while searching (the guard clauses in api/lobby/public.lua that
-- call MPAPI.matchmaking.guard_queued). Not wired into a test framework (the
-- repo has none) -- this is a self-contained LuaJIT script that stubs just
-- enough of the Balatro/MPAPI surface to load and drive the real module source.
--
-- Run: luajit dev/test_queue_guard.lua

local this_dir = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') or './'
local GUARD_PATH = this_dir .. '../api/matchmaking/queue_guard.lua'
local PUBLIC_PATH = this_dir .. '../api/lobby/public.lua'

local function read_file(path)
	local f = assert(io.open(path, 'r'))
	local content = f:read('*a')
	f:close()
	return content
end

local function strip_exact(src, needle)
	local s, e = src:find(needle, 1, true) -- plain (non-pattern) find
	assert(s, 'failed to construct pre-fix control variant (block not found verbatim)')
	return src:sub(1, s - 1) .. src:sub(e + 1)
end

local guard_src = read_file(GUARD_PATH)
local public_src = read_file(PUBLIC_PATH)

-- The "broken" control variant of the run gate reproduces the pre-fix behaviour
-- (no gate at all -- G.FUNCS.start_run falls straight through to the original),
-- so the regression test can prove it would actually have failed before the fix.
local RUN_GATE_BLOCK = [[
	-- The replay closure re-enters the wrapper (not _start_run_ref) so the gate
	-- re-checks on the way through, matching the lobby entry points.
	if MPAPI.matchmaking.guard_queued(function() return G.FUNCS.start_run(e, args) end) then
		return
	end
]]

-- The "broken" control variants of the lobby gates (no guard clause -- create /
-- join proceed straight to allocating a server lobby even while searching).
local CREATE_GATE_BLOCK = [[

	-- Block player-initiated lobby creation while a matchmaking search is active
	-- (same rule as run-start). Matchmaking never trips this: create_lobby is
	-- only ever called for custom lobbies -- the server allocates the matchmade
	-- lobby and clients only join it, and that auto-join runs after the handle
	-- has a match_id, so is_queued() is already false.
	if MPAPI.matchmaking.guard_queued(function() return MPAPI.create_lobby(mod_id, opts) end) then
		return nil
	end
]]

local JOIN_GATE_BLOCK = [[

	-- Block player-initiated joins while searching. Matchmaking's own auto-join
	-- (dispatch.on_match_found) is unaffected: it runs after the matched handle
	-- has a match_id, so is_queued() is already false by the time it calls here.
	if MPAPI.matchmaking.guard_queued(function() return MPAPI.join_lobby(mod_id, code, opts) end) then
		return nil
	end
]]

local broken_guard_src = strip_exact(guard_src, RUN_GATE_BLOCK)
assert(broken_guard_src ~= guard_src, 'run-gate control variant did not change source')
local broken_public_src = strip_exact(strip_exact(public_src, CREATE_GATE_BLOCK), JOIN_GATE_BLOCK)
assert(broken_public_src ~= public_src, 'lobby-gate control variant did not change source')

------------------------
-- Test harness
------------------------

local failures = 0
local function check(cond, msg)
	if cond then
		print('PASS: ' .. msg)
	else
		failures = failures + 1
		print('FAIL: ' .. msg)
	end
end

local function load_chunk(src, name, env)
	local chunk = assert(loadstring(src, name))
	setfenv(chunk, setmetatable(env, { __index = _G }))
	chunk()
end

-------------------------------------------------------------------
-- Environment for the run gate (queue_guard.lua wrapping start_run)
-------------------------------------------------------------------

local function make_run_env()
	local original_start_run_calls = 0
	local last_start_run_args = nil
	local overlay_shown_count = 0
	local _searching = false

	local G = {
		FUNCS = {
			-- Stand-in for the vanilla G.FUNCS.start_run this module wraps.
			start_run = function(_e, _args)
				original_start_run_calls = original_start_run_calls + 1
				last_start_run_args = _args
			end,
		},
		SETTINGS = { paused = false },
	}

	local MPAPI = {
		_internal = {},
		matchmaking = {
			is_queued = function() return _searching end,
		},
		queue_guard_overlay = {
			as_overlay = function() overlay_shown_count = overlay_shown_count + 1 end,
		},
	}

	return {
		G = G,
		MPAPI = MPAPI,
		set_searching = function(v) _searching = v end,
		start_run_calls = function() return original_start_run_calls end,
		last_start_run_args = function() return last_start_run_args end,
		overlay_shown_count = function() return overlay_shown_count end,
		call_start_run = function() G.FUNCS.start_run(nil, {}) end,
	}
end

local function load_run_guard(src, env)
	load_chunk(src, 'queue_guard', { G = env.G, MPAPI = env.MPAPI })
end

------------------------
-- Run gate: not searching -> start_run proceeds untouched (zero overhead)
------------------------

print()
print('-- run gate: fixed, not searching --')
local env1 = make_run_env()
load_run_guard(guard_src, env1)
env1.set_searching(false)
env1.call_start_run()
check(env1.start_run_calls() == 1, 'fixed: original start_run called when not searching')
check(env1.overlay_shown_count() == 0, 'fixed: guard overlay not shown when not searching')

------------------------
-- Run gate: searching -> start_run blocked, overlay shown instead
------------------------

print()
print('-- run gate: fixed, searching --')
local env2 = make_run_env()
load_run_guard(guard_src, env2)
env2.set_searching(true)
env2.call_start_run()
check(env2.start_run_calls() == 0, 'fixed: original start_run NOT called while searching')
check(env2.overlay_shown_count() == 1, 'fixed: guard overlay shown while searching')

------------------------
-- Run gate: "Leave Queue & Continue" -- blocked action stashed as a replay
-- closure, replaying it after leaving proceeds through the (now-open) gate
------------------------

print()
print('-- run gate: leave queue and continue (stash + replay) --')
local env3 = make_run_env()
load_run_guard(guard_src, env3)
env3.set_searching(true)
local marker_args = { tag = 'replay-me' }
env3.G.FUNCS.start_run(nil, marker_args)
local mm3 = env3.MPAPI._internal.mm
check(env3.start_run_calls() == 0, 'leave-and-continue: blocked while searching')
check(type(mm3.pending_action) == 'function', 'leave-and-continue: blocked action stashed as a replay closure')

-- Simulate the overlay button: leave queue (is_queued flips false), replay.
env3.set_searching(false)
local action3 = mm3.pending_action
mm3.pending_action = nil
action3()
check(env3.start_run_calls() == 1, 'leave-and-continue: replayed action proceeds after leaving')
check(env3.last_start_run_args() == marker_args, 'leave-and-continue: replay carried the original args')

-- Replay must re-check the gate: if still searching, it re-blocks.
local env3b = make_run_env()
load_run_guard(guard_src, env3b)
env3b.set_searching(true)
env3b.call_start_run()
local mm3b = env3b.MPAPI._internal.mm
local action3b = mm3b.pending_action
action3b() -- still searching
check(env3b.start_run_calls() == 0, 'leave-and-continue: replay while STILL searching re-blocks (no run starts)')

------------------------
-- Run gate RED control: pre-fix source has no gate -- run starts while searching
------------------------

print()
print('-- run gate: pre-fix control (proves the test is meaningful) --')
local env_broken = make_run_env()
load_run_guard(broken_guard_src, env_broken)
env_broken.set_searching(true)
env_broken.call_start_run()
check(env_broken.start_run_calls() == 1, 'broken: (control) start_run proceeds even while searching -- reproduces the bug')
check(env_broken.overlay_shown_count() == 0, 'broken: (control) no guard overlay ever shown')

-------------------------------------------------------------------
-- Environment for the lobby gates (public.lua create/join). Loads the REAL
-- queue_guard.lua too, so create/join exercise the real guard_queued.
-------------------------------------------------------------------

local function make_lobby_env()
	local overlay_shown_count = 0
	local create_objects = 0        -- L.create_object calls (a lobby was allocated)
	local server_create_calls = 0   -- conn.api:create_lobby calls
	local server_join_calls = 0     -- conn.api:join_lobby calls
	local _searching = false

	local G = { FUNCS = {}, SETTINGS = { paused = false } }

	local conn = {
		player_id = 'p1',
		jwt_token = 'jwt',
		get_state = function() return 'connected' end,
		api = {
			create_lobby = function() server_create_calls = server_create_calls + 1 end,
			join_lobby = function() server_join_calls = server_join_calls + 1 end,
		},
	}

	local MPAPI = {
		_internal = { lobby = {} },
		matchmaking = {
			is_queued = function() return _searching end,
		},
		queue_guard_overlay = {
			as_overlay = function() overlay_shown_count = overlay_shown_count + 1 end,
		},
		ConnectionState = { CONNECTED = 'connected' },
		get_connection = function() return conn end,
		get_mqtt = function() return {} end,
		sendWarnMessage = function() end,
		sendDebugMessage = function() end,
	}
	-- L.create_object: return a minimal lobby object, count allocations.
	MPAPI._internal.lobby.create_object = function(_cfg)
		create_objects = create_objects + 1
		return { _players = {}, on = function() end, _fire = function() end }
	end

	return {
		G = G,
		MPAPI = MPAPI,
		set_searching = function(v) _searching = v end,
		overlay_shown_count = function() return overlay_shown_count end,
		create_objects = function() return create_objects end,
		server_create_calls = function() return server_create_calls end,
		server_join_calls = function() return server_join_calls end,
	}
end

local function load_lobby_modules(public_variant, env)
	-- queue_guard.lua first so MPAPI.matchmaking.guard_queued exists, then public.lua.
	load_chunk(guard_src, 'queue_guard', { G = env.G, MPAPI = env.MPAPI })
	load_chunk(public_variant, 'public', { G = env.G, MPAPI = env.MPAPI })
end

------------------------
-- Lobby gate: not searching -> create/join proceed (allocate a lobby)
------------------------

print()
print('-- lobby gate: fixed, not searching --')
local lenv1 = make_lobby_env()
load_lobby_modules(public_src, lenv1)
lenv1.set_searching(false)
local created = lenv1.MPAPI.create_lobby('mod', { max_players = 2 })
check(created ~= nil, 'fixed: create_lobby returns a lobby when not searching')
check(lenv1.create_objects() == 1 and lenv1.server_create_calls() == 1, 'fixed: create_lobby allocated a lobby when not searching')
local joined = lenv1.MPAPI.join_lobby('mod', 'ABCD')
check(joined ~= nil, 'fixed: join_lobby returns a lobby when not searching')
check(lenv1.server_join_calls() == 1, 'fixed: join_lobby hit the server when not searching')
check(lenv1.overlay_shown_count() == 0, 'fixed: no guard overlay when not searching')

------------------------
-- Lobby gate: searching -> create/join blocked, overlay shown, nothing allocated
------------------------

print()
print('-- lobby gate: fixed, searching --')
local lenv2 = make_lobby_env()
load_lobby_modules(public_src, lenv2)
lenv2.set_searching(true)
local created2 = lenv2.MPAPI.create_lobby('mod', { max_players = 2 })
check(created2 == nil, 'fixed: create_lobby returns nil while searching')
check(lenv2.create_objects() == 0 and lenv2.server_create_calls() == 0, 'fixed: create_lobby allocated NOTHING while searching')
local joined2 = lenv2.MPAPI.join_lobby('mod', 'ABCD')
check(joined2 == nil, 'fixed: join_lobby returns nil while searching')
check(lenv2.server_join_calls() == 0, 'fixed: join_lobby did NOT hit the server while searching')
check(lenv2.overlay_shown_count() == 2, 'fixed: guard overlay shown for each blocked attempt')
check(type(lenv2.MPAPI._internal.mm.pending_action) == 'function', 'fixed: blocked lobby action stashed as a replay closure')

-- "Leave Queue & Continue": leave (is_queued false) then replay the closure ->
-- the create now proceeds through the guarded entry point.
lenv2.set_searching(false)
local laction = lenv2.MPAPI._internal.mm.pending_action
laction()
check(lenv2.create_objects() == 1, 'leave-and-continue: replayed lobby action proceeds after leaving')

------------------------
-- Lobby gate: matchmaking auto-join is SAFE -- a matched handle makes
-- is_queued() false, so dispatch's join_lobby is never blocked.
------------------------

print()
print('-- lobby gate: matchmaking auto-join unaffected --')
local lenv3 = make_lobby_env()
load_lobby_modules(public_src, lenv3)
lenv3.set_searching(false) -- match found: handle carries a match_id -> not searching
local autojoin = lenv3.MPAPI.join_lobby('mod', 'MATCHCODE')
check(autojoin ~= nil and lenv3.server_join_calls() == 1, 'auto-join: join proceeds once matched (is_queued false)')
check(lenv3.overlay_shown_count() == 0, 'auto-join: no guard overlay for the matchmade join')

------------------------
-- Lobby gate RED control: pre-fix source has no gate -- create/join proceed
-- (allocate a lobby) even while searching.
------------------------

print()
print('-- lobby gate: pre-fix control (proves the test is meaningful) --')
local lenv_broken = make_lobby_env()
load_lobby_modules(broken_public_src, lenv_broken)
lenv_broken.set_searching(true)
local cbroken = lenv_broken.MPAPI.create_lobby('mod', { max_players = 2 })
check(cbroken ~= nil and lenv_broken.create_objects() == 1, 'broken: (control) create_lobby allocates a lobby even while searching -- reproduces the bug')
local jbroken = lenv_broken.MPAPI.join_lobby('mod', 'ABCD')
check(jbroken ~= nil and lenv_broken.server_join_calls() == 1, 'broken: (control) join_lobby hits the server even while searching -- reproduces the bug')
check(lenv_broken.overlay_shown_count() == 0, 'broken: (control) no guard overlay ever shown')

------------------------
-- handle:leave() fires the "left" event exactly once
------------------------

print()
print('-- matchmaking handle fires left on leave() --')
local HANDLE_SRC = read_file(this_dir .. '../api/matchmaking/handle.lua')
local handle_MPAPI = {
	matchmaking = {},
	_internal = { mm = { remove_handle = function() end } },
	get_connection = function() return nil end,
	sendWarnMessage = function() end,
}
local handle_chunk = assert(loadstring(HANDLE_SRC, 'handle'))
setfenv(handle_chunk, setmetatable({ MPAPI = handle_MPAPI }, { __index = _G }))
handle_chunk()

local h = handle_MPAPI.matchmaking._make_handle('TestMod', 'test_mode')
local left_fired = 0
h:on('left', function() left_fired = left_fired + 1 end)
h:leave()
check(left_fired == 1, 'handle: left event fired on leave()')
h:leave()
check(left_fired == 1, 'handle: left event NOT re-fired on a duplicate leave()')

------------------------

print()
if failures == 0 then
	print('ALL TESTS PASSED')
	os.exit(0)
else
	print(failures .. ' TEST(S) FAILED')
	os.exit(1)
end
