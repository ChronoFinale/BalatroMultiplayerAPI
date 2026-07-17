-- Server-generated draft support (OPT-IN). Consumers that never call these keep
-- fully client-side drafts; servers without the endpoints 404 into the fallback.
--
-- The contract with consumers:
--   fetch_draft_pool(match_id, cb)  -> cb(pool) with an array of { key, stake }
--                                      items ready for BanPick, or cb(nil) on ANY
--                                      failure (no connection, no match id, no
--                                      policy for the queue, transport error) --
--                                      nil always means "generate locally".
--   record_draft_event(match_id, e) -> fire-and-forget audit post; e = { seq,
--                                      action = 'ban'|'pick', key, stake }.
--                                      Failures are logged, never surfaced.

MPAPI.matchmaking = MPAPI.matchmaking or {}

function MPAPI.matchmaking.fetch_draft_pool(match_id, callback, opts)
	local conn = MPAPI.get_connection()
	if not conn or not conn.api or not conn.jwt_token or not match_id then
		callback(nil)
		return
	end
	local max_stake = opts and opts.max_stake or nil
	conn.api:issue_draft_pool(conn.jwt_token, match_id, max_stake, function(err, data)
		if err or not data or type(data.pool) ~= 'table' then
			if err then
				MPAPI.sendDebugMessage('[draft] pool fetch failed (falling back to local): ' .. tostring(err.message or err))
			end
			callback(nil)
			return
		end
		-- The pool is a list of self-describing items: { key, stake }, and for a
		-- composite deck additionally { decks = { key, ... }, name? } -- the
		-- composition rides on the item, so there is no separate config fetch.
		callback(data.pool)
	end)
end

function MPAPI.matchmaking.record_draft_event(match_id, event)
	local conn = MPAPI.get_connection()
	if not conn or not conn.api or not conn.jwt_token or not match_id then
		return
	end
	conn.api:record_draft_event(conn.jwt_token, match_id, event, function(err, _data)
		if err then
			MPAPI.sendDebugMessage('[draft] event post failed (seq=' .. tostring(event.seq) .. '): ' .. tostring(err.message or err))
		end
	end)
end
