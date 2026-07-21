local api_client = MPAPI.networking.api_client

-- POST /api/matches/:id/draft-pool. Idempotent server-side: the first call rolls
-- and persists the pool, every retry/reconnect returns the identical pool.
-- 404 = the queue has no draft policy -- the caller's signal to abort the draft.
function api_client:issue_draft_pool(token, match_id, callback)
	if not self:_transport_ready() then
		callback(MPAPI.make_error(MPAPI.ErrorKind.NOT_CONNECTED, 'MQTT thread not running'), nil)
		return
	end

	self:_setup_json_callback(callback)

	self.mqtt:http_post_auth(self.base_url .. '/api/matches/' .. match_id .. '/draft-pool', '{}', token)
end

-- POST /api/matches/:id/draft-events. Audit stash for applied draft actions;
-- `event.seq` dedups transport retries server-side (upsert by (match, seq)).
function api_client:record_draft_event(token, match_id, event, callback)
	if not self:_transport_ready() then
		callback(MPAPI.make_error(MPAPI.ErrorKind.NOT_CONNECTED, 'MQTT thread not running'), nil)
		return
	end

	self:_setup_json_callback(callback)

	local body = api_client.json_encode(event)
	self.mqtt:http_post_auth(self.base_url .. '/api/matches/' .. match_id .. '/draft-events', body, token)
end
