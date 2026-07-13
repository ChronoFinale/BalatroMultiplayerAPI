-- Standalone regression test for api/matchmaking/run_guard.lua's queue-blocks-
-- run-start gate. Not wired into a test framework (the repo has none) -- this
-- is a self-contained LuaJIT script that stubs just enough of the Balatro/
-- MPAPI surface (G.FUNCS, G.SETTINGS, MPAPI.matchmaking.is_queued,
-- MPAPI.queue_guard_overlay) to load and drive the real module source.
--
-- Run: luajit dev/test_queue_guard.lua

local this_dir = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') or './'
local SRC_PATH = this_dir .. '../api/matchmaking/run_guard.lua'

local function read_file(path)
	local f = assert(io.open(path, 'r'))
	local content = f:read('*a')
	f:close()
	return content
end

local fixed_src = read_file(SRC_PATH)

-- The "broken" control variant reproduces the pre-fix behaviour (no gate at
-- all -- G.FUNCS.start_run falls straight through to the original), so the
-- regression test can prove it would actually have failed before the fix.
local GATE_BLOCK = [[
	if mm.run_gate_decision(MPAPI.matchmaking.is_queued()) == 'block' then
		if MPAPI.queue_guard_overlay then
			G.SETTINGS.paused = true
			MPAPI.queue_guard_overlay:as_overlay()
		end
		return
	end
]]

local function strip_exact(src, needle)
	local s, e = src:find(needle, 1, true) -- plain (non-pattern) find
	assert(s, 'failed to construct pre-fix control variant (gate block not found verbatim)')
	return src:sub(1, s - 1) .. src:sub(e + 1)
end

local broken_src = strip_exact(fixed_src, GATE_BLOCK)
assert(broken_src ~= fixed_src, 'control variant did not change source')

-------------------------------------------------------------------
-- Fake environment: G.FUNCS, G.SETTINGS, MPAPI
-------------------------------------------------------------------

local function make_env()
	local original_start_run_calls = 0
	local overlay_shown_count = 0
	local _searching = false

	local G = {
		FUNCS = {
			-- Stand-in for the vanilla G.FUNCS.start_run this module wraps.
			start_run = function(_e, _args)
				original_start_run_calls = original_start_run_calls + 1
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
		overlay_shown_count = function() return overlay_shown_count end,
		call_start_run = function() G.FUNCS.start_run(nil, {}) end,
	}
end

local function load_module(src, env)
	local chunk_env = setmetatable({ G = env.G, MPAPI = env.MPAPI }, { __index = _G })
	local chunk = assert(loadstring(src, 'run_guard'))
	setfenv(chunk, chunk_env)
	chunk()
end

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

------------------------
-- Test 1: pure gate function -- allow when not searching, block when searching
------------------------

print('-- scenario: pure mm.run_gate_decision --')
local env1 = make_env()
load_module(fixed_src, env1)
local mm1 = env1.MPAPI._internal.mm

check(mm1.run_gate_decision(false) == 'allow', 'pure: not searching -> allow')
check(mm1.run_gate_decision(true) == 'block', 'pure: searching -> block')

------------------------
-- Test 2 (fixed): not searching -> start_run proceeds untouched (zero overhead)
------------------------

print()
print('-- scenario: fixed run_guard.lua, not searching --')
local env2 = make_env()
load_module(fixed_src, env2)
env2.set_searching(false)
env2.call_start_run()
check(env2.start_run_calls() == 1, 'fixed: original start_run called when not searching')
check(env2.overlay_shown_count() == 0, 'fixed: guard overlay not shown when not searching')

------------------------
-- Test 3 (fixed): searching -> start_run blocked, overlay shown instead
------------------------

print()
print('-- scenario: fixed run_guard.lua, searching --')
local env3 = make_env()
load_module(fixed_src, env3)
env3.set_searching(true)
env3.call_start_run()
check(env3.start_run_calls() == 0, 'fixed: original start_run NOT called while searching')
check(env3.overlay_shown_count() == 1, 'fixed: guard overlay shown while searching')

------------------------
-- Test 4 (fixed): leave-queue-then-allow sequence
------------------------

print()
print('-- scenario: fixed run_guard.lua, leave queue then retry --')
local env4 = make_env()
load_module(fixed_src, env4)
env4.set_searching(true)
env4.call_start_run()
check(env4.start_run_calls() == 0, 'leave-then-allow: blocked while still searching')
check(env4.overlay_shown_count() == 1, 'leave-then-allow: overlay shown while still searching')

-- Simulate "Leave Queue": the handle leaves, is_queued() flips false.
env4.set_searching(false)
env4.call_start_run()
check(env4.start_run_calls() == 1, 'leave-then-allow: start_run proceeds once no longer searching')

------------------------
-- Test 5 (RED control): pre-fix source has no gate -- run starts while searching
------------------------

print()
print('-- scenario: pre-fix run_guard.lua (control, proves the test is meaningful) --')
local broken_env = make_env()
load_module(broken_src, broken_env)
broken_env.set_searching(true)
broken_env.call_start_run()
check(broken_env.start_run_calls() == 1, 'broken: (control) start_run proceeds even while searching -- reproduces the bug')
check(broken_env.overlay_shown_count() == 0, 'broken: (control) no guard overlay ever shown')

------------------------

print()
if failures == 0 then
	print('ALL TESTS PASSED')
	os.exit(0)
else
	print(failures .. ' TEST(S) FAILED')
	os.exit(1)
end
