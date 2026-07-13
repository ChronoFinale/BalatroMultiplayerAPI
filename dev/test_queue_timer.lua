-- Standalone regression test for api/matchmaking/queue_timer.lua's run-start
-- survival fix. Not wired into a test framework (the repo has none) -- this is
-- a self-contained LuaJIT script that stubs just enough of the Balatro/Love2D
-- surface (G.E_MANAGER, Event, love.timer, localize, MPAPI) to load and drive
-- the real module source.
--
-- Run: luajit dev/test_queue_timer.lua

local this_dir = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') or './'
local SRC_PATH = this_dir .. '../api/matchmaking/queue_timer.lua'

local function read_file(path)
	local f = assert(io.open(path, 'r'))
	local content = f:read('*a')
	f:close()
	return content
end

local fixed_src = read_file(SRC_PATH)

-- The "broken" control variant reproduces the pre-fix source (no `no_delete`
-- flag on the tick event), so the regression test can prove it actually would
-- have failed before the fix.
local broken_src = fixed_src:gsub('\n%s*no_delete = true,\n', '\n')
assert(broken_src ~= fixed_src, 'failed to construct pre-fix control variant (no_delete line not found)')

-------------------------------------------------------------------
-- Fake environment: G.E_MANAGER, Event, love.timer, localize, MPAPI
-------------------------------------------------------------------

local function make_env()
	local queue = {}
	local fake_now = 0
	local status_calls = {}
	local status_call_count = 0

	local G = {
		E_MANAGER = {
			add_event = function(_, event)
				event._remaining = event.delay or 0
				queue[#queue + 1] = event
			end,
			-- Mirrors Balatro's clear_queue(): drops every pending event that isn't
			-- flagged no_delete. Called by Game:start_run / G:delete_run.
			clear_queue = function(_)
				local kept = {}
				for _, event in ipairs(queue) do
					if event.no_delete then
						kept[#kept + 1] = event
					end
				end
				queue = kept
			end,
		},
	}

	local function Event(opts)
		return opts
	end

	local love = { timer = { getTime = function() return fake_now end } }

	local function localize(key)
		return key
	end

	local MPAPI = {
		_internal = {},
		matchmaking = {},
		set_connection_status = function(text)
			status_call_count = status_call_count + 1
			status_calls[status_call_count] = text
		end,
	}

	-- Advance the fake wall clock and fire any events whose delay has elapsed --
	-- a minimal stand-in for G.E_MANAGER's per-frame update loop.
	local function tick_event_manager(dt)
		fake_now = fake_now + dt
		local due, remaining = {}, {}
		for _, event in ipairs(queue) do
			event._remaining = event._remaining - dt
			if event._remaining <= 0 then
				due[#due + 1] = event
			else
				remaining[#remaining + 1] = event
			end
		end
		queue = remaining
		for _, event in ipairs(due) do
			event.func()
		end
	end

	return {
		G = G,
		Event = Event,
		love = love,
		localize = localize,
		MPAPI = MPAPI,
		tick_event_manager = tick_event_manager,
		clear_queue = function() G.E_MANAGER.clear_queue(G.E_MANAGER) end,
		queue_len = function() return #queue end,
		status_call_count = function() return status_call_count end,
		last_status = function() return status_calls[status_call_count] end,
	}
end

local function load_module(src, env)
	local chunk_env = setmetatable({
		G = env.G,
		Event = env.Event,
		love = env.love,
		localize = env.localize,
		MPAPI = env.MPAPI,
	}, { __index = _G })
	local chunk = assert(loadstring(src, 'queue_timer'))
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
-- Test 1 (regression): pending tick survives a simulated clear_queue()
------------------------

print('-- scenario: fixed queue_timer.lua --')
local env = make_env()
load_module(fixed_src, env)
local mm = env.MPAPI._internal.mm

-- One handle actively searching, so the timer has a reason to keep ticking.
mm.handles = { {} }

mm.queue_timer.start()
check(env.queue_len() == 1, 'fixed: tick scheduled after start()')

-- Simulate Game:start_run() / G:delete_run() firing mid-queue.
env.clear_queue()
check(env.queue_len() == 1, 'fixed: pending tick survives clear_queue() (the regression)')

-- Advance past the 0.25s delay and confirm the tick actually fires and re-arms.
env.tick_event_manager(0.25)
check(env.queue_len() == 1, 'fixed: tick fired and re-armed the next tick after surviving clear_queue()')
check(env.status_call_count() >= 2, 'fixed: status text was updated by the post-clear-queue tick')

print()
print('-- scenario: pre-fix queue_timer.lua (control, proves the test is meaningful) --')
local broken_env = make_env()
load_module(broken_src, broken_env)
local broken_mm = broken_env.MPAPI._internal.mm
broken_mm.handles = { {} }
broken_mm.queue_timer.start()
check(broken_env.queue_len() == 1, 'broken: tick scheduled after start()')
broken_env.clear_queue()
check(broken_env.queue_len() == 0, 'broken: (control) pending tick is purged by clear_queue(), reproducing the bug')

------------------------
-- Test 2: loop still self-terminates once searching stops
------------------------

print()
print('-- scenario: loop terminates when any_searching() goes false --')
local term_env = make_env()
load_module(fixed_src, term_env)
local term_mm = term_env.MPAPI._internal.mm

term_mm.handles = { {} }
term_mm.queue_timer.start()
check(term_env.queue_len() == 1, 'terminate: tick scheduled after start()')

term_env.tick_event_manager(0.25)
check(term_env.queue_len() == 1, 'terminate: still searching, tick re-armed')
check(term_env.MPAPI.matchmaking.is_queued() == true, 'terminate: is_queued() true while searching')

-- Handle leaves the queue (matched, cancelled, or errored).
term_mm.handles[1]._left = true
term_env.tick_event_manager(0.25)

check(term_env.queue_len() == 0, 'terminate: no further tick scheduled once any_searching() is false')
check(term_env.MPAPI.matchmaking.is_queued() == false, 'terminate: is_queued() false once handle has left')
check(term_env.last_status() == nil, 'terminate: status override cleared (nil) by stop()')

------------------------

print()
if failures == 0 then
	print('ALL TESTS PASSED')
	os.exit(0)
else
	print(failures .. ' TEST(S) FAILED')
	os.exit(1)
end
