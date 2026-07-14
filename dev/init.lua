-- Dev overrides: This file (and the dev/ directory) is stripped from release builds by CI.
local connection = MPAPI.networking.connection

-- Logs in via an ephemeral dev/temp account (random in-memory player id, not
-- persisted to the DB). A temp account can never queue matchmaking or appear on the
-- leaderboard (no players row), so this is commented out to fall back to real Steam
-- auth. Uncomment to use a throwaway dev account instead.
-- function connection._do_auth(self)
-- 	self:_try_dev_auth()
-- end

-- Impersonation: log in as an EXISTING player (real players row), so it can queue
-- matchmaking and appear on the leaderboard. This lets a second game instance act as
-- a different real account without a second Steam login -- useful for testing
-- matchmaking locally. Enable per-instance by setting one of these env vars before
-- launching that instance (the other instance, with neither set, uses real Steam):
--   BMP_IMPERSONATE_ID=<players.id uuid>
--   BMP_IMPERSONATE_NAME=<steamName>      e.g. a seeded "Runner001"
local imp_id = os.getenv('BMP_IMPERSONATE_ID')
local imp_name = os.getenv('BMP_IMPERSONATE_NAME')
if imp_id or imp_name then
	local target = imp_id and { playerId = imp_id } or { steamName = imp_name }
	function connection._do_auth(self)
		self:_try_impersonate_auth(target)
	end
	MPAPI.sendDebugMessage('Dev impersonation auth enabled for ' .. tostring(imp_id or imp_name))
elseif os.getenv('BMP_DEV_AUTH') then
	-- Ephemeral throwaway account (no Steam, no players row). Set BMP_DEV_AUTH=1
	-- to skip Steam login entirely — handy for local chat/moderation testing.
	-- connect() normally hard-gates on G.STEAM before auth runs, so on a machine
	-- with no Steam API we must override connect() itself, not just _do_auth.
	function connection._do_auth(self)
		self:_try_dev_auth()
	end
	function connection.connect(self)
		if self.state ~= MPAPI.ConnectionState.DISCONNECTED then
			return
		end
		self:_try_dev_auth()
	end
	MPAPI.sendDebugMessage('Dev auth (ephemeral, Steam-free) enabled via BMP_DEV_AUTH')
end

MPAPI.sendDebugMessage('Dev auth overrides applied')
