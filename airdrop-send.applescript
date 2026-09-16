-- airdrop-send.applescript — open the AirDrop picker preloaded with the given files.
--
-- Run by the Finder Quick Action (see install-quick-action.sh):
--     osascript airdrop-send.applescript <path> [<path> ...]
--
-- ⚠️ Three things were tried here and MUST NOT be reintroduced; each one stops
-- the picker from appearing at all, and each looks like an improvement:
--
--   1. setActivationPolicy: / activateIgnoringOtherApps:  — "make it a proper
--      foreground app so the panel keeps focus". The panel then never shows.
--   2. Compiling this into an .app (droplet, or stay-open applet with on idle)
--      — same result: `on open` runs, performWithItems: returns, no picker.
--   3. A completion delegate that exits when the share finishes. See below.
--
-- Plain osascript with a pumped run loop and no activation is the ONE shape
-- that displays the picker. Verified by screenshot each way on macOS 26.5.1.
use framework "Foundation"
use framework "AppKit"
use scripting additions

on run argv
	if (count of argv) is 0 then return "no files"
	set urls to current application's NSMutableArray's array()
	repeat with p in argv
		urls's addObject:(current application's NSURL's fileURLWithPath:(p as text))
	end repeat
	set svc to current application's NSSharingService's sharingServiceNamed:"com.apple.share.AirDrop.send"
	if svc is missing value then return "AirDrop service unavailable"

	svc's performWithItems:urls

	-- Pump the run loop, not `delay`: the picker belongs to THIS process and
	-- dies with it, and `delay` does not reliably run the loop.
	--
	-- ⚠️ There is deliberately NO completion delegate. The first version set a
	-- flag in sharingService:didShareItems: and exited the loop when it fired --
	-- but that callback fires when you PICK A RECIPIENT, not when the file has
	-- arrived. Exiting there killed the process mid-handoff: the picker closed
	-- on the click and nothing was ever sent. That was the whole bug.
	--
	-- So it simply outlives the transfer: 3600 x 0.25s = 900s, long enough for
	-- a large file over a slow link. The process is idle and invisible, and the
	-- wrapper kills the previous one on the next invocation, so at most one is
	-- ever waiting.
	set rl to current application's NSRunLoop's currentRunLoop()
	repeat 3600 times
		rl's runUntilDate:(current application's NSDate's dateWithTimeIntervalSinceNow:0.25)
	end repeat
	return "done"
end run
