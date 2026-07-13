-- Blocks vanilla singleplayer run-start while a matchmaking search is active.
-- Bug: nothing stopped a queued player from clicking Play -> New Run (or
-- Continue / a Challenge); the run would tear down the main menu while the
-- queue stayed active server-side with no feedback. Maintainer verdict: you
-- should not be able to start a run at all while queued.
MPAPI.matchmaking = MPAPI.matchmaking or {}
MPAPI._internal.mm = MPAPI._internal.mm or {}
local mm = MPAPI._internal.mm

-- Pure: decide whether a run-start action may proceed, given only whether a
-- matchmaking search is currently active. Plain bool in, plain enum out --
-- exhaustively unit-testable with no G/Event/MPAPI stubbing required.
function mm.run_gate_decision(is_searching)
	return is_searching and 'block' or 'allow'
end

-- Shell: G.FUNCS.start_run is the single vanilla chokepoint every "enter a run"
-- flow funnels through -- New Run and Continue (via start_setup_run), Challenges
-- (via start_challenge_run), the first-launch tutorial run, and the in-run
-- "Start New Run" restart button all call it directly. It is also the function
-- that actually tears down the menu (G.E_MANAGER:clear_queue(), wipe_on/off)
-- and calls Game:start_run -- gating here, before any of that runs, catches
-- every one of those entry points with a single wrap and leaves the menu
-- completely untouched when blocked.
local _start_run_ref = G.FUNCS.start_run
G.FUNCS.start_run = function(e, args)
	if mm.run_gate_decision(MPAPI.matchmaking.is_queued()) == 'block' then
		if MPAPI.queue_guard_overlay then
			G.SETTINGS.paused = true
			MPAPI.queue_guard_overlay:as_overlay()
		end
		return
	end
	return _start_run_ref(e, args)
end
