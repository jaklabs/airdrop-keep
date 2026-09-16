-- airdrop-send.applescript — open the AirDrop picker preloaded with the given files.
use framework "Foundation"
use framework "AppKit"
use scripting additions

property finished : false

script ShareDelegate
	on sharingService:svc didShareItems:sharedItems
		set finished to true
	end
end script

on run argv
	if (count of argv) is 0 then return "no files"
	set urls to current application's NSMutableArray's array()
	repeat with p in argv
		urls's addObject:(current application's NSURL's fileURLWithPath:(p as text))
	end repeat
	set svc to current application's NSSharingService's sharingServiceNamed:"com.apple.share.AirDrop.send"
	if svc is missing value then return "AirDrop service unavailable"
	svc's setDelegate:ShareDelegate
	svc's performWithItems:urls
	-- Pump the real run loop, not `delay`: the panel belongs to THIS process and
	-- dies with it, and delegate callbacks only fire while the loop is running.
	-- 600 x 0.25s = 150s. There is an upper bound because AppleScript cannot
	-- implement the cancel callback: the selector is sharingService:didFail-
	-- ToShareItems:error:, and `error` is a reserved word that cannot appear as
	-- a handler label -- so a CANCELLED share never calls back and would
	-- otherwise hold this process forever. Success exits immediately via the
	-- delegate below; cancel costs an idle, invisible process until the timeout.
	-- The wrapper kills a previous one on the next invocation, so at most one
	-- is ever waiting.
	set rl to current application's NSRunLoop's currentRunLoop()
	repeat 600 times
		if finished then exit repeat
		rl's runUntilDate:(current application's NSDate's dateWithTimeIntervalSinceNow:0.25)
	end repeat
	if finished then
		return "done"
	else
		return "timeout"
	end if
end run
