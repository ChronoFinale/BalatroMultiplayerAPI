--[[
  Lobby leave teardown test.

  A leave must always COMPLETE locally: every teardown consumer (view reset,
  match handles, ban-pick) hangs off LobbyEvent.DISCONNECTED, so the local
  cleanup + DISCONNECTED path must run even when the leave_lobby HTTP
  round-trip errors (the lobby lingering server-side is acceptable and logged).

  Run from the repo root:
    luajit dev/test_lobby_leave.lua
]]

-- ── Stubs to load the real modules ──────────────────────────────────────────
MPAPI = {}
MPAPI._internal = {}
local warns = {}
MPAPI.sendWarnMessage = function(msg)
	warns[#warns + 1] = msg
end
MPAPI.json_encode = function(_t)
	return '{}'
end
MPAPI.config = { chat_enabled = false }
MPAPI.chat = { cleanup = function() end }
MPAPI.ActionType = { obj_buffer = {} }
MPAPI.ActionTypes = {}

dofile('domain/result.lua')
dofile('domain/lobby_event.lua')
dofile('api/lobby/state.lua')

local L = MPAPI._internal.lobby

local hook_calls = 0
MPAPI._internal.on_lobby_disconnected = function()
	hook_calls = hook_calls + 1
end

-- leave_result.err / .data are handed to the leave_lobby callback verbatim.
local function new_lobby(leave_result)
	local unsubs = {}
	local mqtt = {
		lobby_topic = function(_self, code, suffix)
			return code .. '/' .. suffix
		end,
		unsubscribe = function(_self, topic)
			unsubs[#unsubs + 1] = topic
		end,
		publish = function() end,
	}
	local api = {
		leave_lobby = function(_self, _jwt, _code, cb)
			cb(leave_result.err, leave_result.data)
		end,
	}
	local lobby = L.create_object({
		code = 'ABCD',
		mod_id = 'test',
		is_host = true,
		player_id = 'p1',
		mqtt = mqtt,
		api = api,
		connection = { jwt_token = 'tok0' },
		metadata = {},
	})
	L.current = lobby
	local fired = { disconnected = 0, error = 0 }
	lobby:on(MPAPI.LobbyEvent.DISCONNECTED, function()
		fired.disconnected = fired.disconnected + 1
	end)
	lobby:on(MPAPI.LobbyEvent.ERROR, function(err)
		fired.error = fired.error + 1
		fired.last_error = err
	end)
	return lobby, fired, unsubs
end

-- ── Harness ────────────────────────────────────────────────────────────────
local failures = 0
local function check(cond, msg)
	if cond then print('PASS: ' .. msg) else failures = failures + 1; print('FAIL: ' .. msg) end
end

print()
print('-- successful leave: cleanup + DISCONNECTED + registry hook --')
local lobby, fired, unsubs = new_lobby({ err = nil, data = { token = 'tok1' } })
lobby:leave()
check(lobby._destroyed == true, 'lobby destroyed')
check(L.current == nil, 'active lobby pointer cleared')
check(#unsubs == 5, 'all lobby MQTT topics unsubscribed')
check(fired.disconnected == 1, 'DISCONNECTED fired')
check(fired.error == 0, 'no ERROR on success')
check(hook_calls == 1, 'on_lobby_disconnected hook ran')
check(lobby._connection.jwt_token == 'tok1', 'rotated token stored')
check(#warns == 0, 'no warning on success')

print()
print('-- leave HTTP error: the SAME local teardown still runs --')
hook_calls = 0
warns = {}
local err = MPAPI.make_error('CONNECTION', 'server exploded')
local lobby2, fired2, unsubs2 = new_lobby({ err = err, data = nil })
lobby2:leave()
check(fired2.error == 1 and fired2.last_error == err, 'ERROR still fired with the round-trip error')
check(lobby2._destroyed == true, 'lobby destroyed despite the error')
check(L.current == nil, 'active lobby pointer cleared despite the error')
check(#unsubs2 == 5, 'MQTT topics unsubscribed despite the error')
check(fired2.disconnected == 1, 'DISCONNECTED fired despite the error (teardown consumers run)')
check(hook_calls == 1, 'on_lobby_disconnected hook ran despite the error')
check(lobby2._connection.jwt_token == 'tok0', 'token unchanged when the server sent none')
check(#warns == 1 and warns[1]:find('server exploded', 1, true) ~= nil, 'server-side lingering is logged as a warning')

print()
print('-- second leave after an errored one is a no-op --')
lobby2:leave()
check(fired2.disconnected == 1 and hook_calls == 1, 'destroyed lobby: leave() does nothing')

print()
print('-- local-mode leave unaffected --')
hook_calls = 0
local lobby3 = L.create_object({
	code = 'LOCL',
	mod_id = 'test',
	is_host = true,
	player_id = 'p1',
	local_mode = true,
	connection = { jwt_token = 'x' },
})
local disc3 = 0
lobby3:on(MPAPI.LobbyEvent.DISCONNECTED, function()
	disc3 = disc3 + 1
end)
lobby3:leave()
check(lobby3._destroyed == true and disc3 == 1 and hook_calls == 1, 'offline lobby tears down in-process')

-- ── Summary ─────────────────────────────────────────────────────────────────
print()
if failures == 0 then
	print('ALL TESTS PASSED')
	os.exit(0)
else
	print(failures .. ' TEST(S) FAILED')
	os.exit(1)
end
