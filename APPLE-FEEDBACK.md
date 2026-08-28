# Apple Feedback — paste-ready

Submit at **[Feedback Assistant](https://feedbackassistant.apple.com)** (or, if enrolled, developer.apple.com/bug-report). Copy each field below into the matching box. This is a **Suggestion / Enhancement**, not a crash.

---

**Title**
> AirDrop should keep a browsable Received history, grouped by transfer

**Area / Component**
> AirDrop (Sharing) · Finder · macOS

**Type of feedback**
> Suggestion / Enhancement request

**Description**
> Files received via AirDrop land in ~/Downloads with no grouping and no history. Over time they intermix by filename with browser downloads and everything else, so relocating a previously-received file is painful. In practice users routinely **re-send the file from the source device just to find it again on the Mac** — a clear signal the received-side experience is missing.
>
> The OS already has everything needed to solve this cleanly: every AirDrop-received file is tagged with the `com.apple.quarantine` extended attribute whose agent field is `sharingd`, and the quarantine record's second field is the precise receive-timestamp. Files from a single transfer therefore share a timestamp and are trivially grouped into a "batch."
>
> **Request:** a Finder "AirDrop — Received" smart location (peer to the existing send-side AirDrop view) that lists received files grouped into per-transfer batches, showing sender and time — so a past transfer can be reopened in one place without any third-party tooling.

**Steps to Reproduce (the pain)**
> 1. Over a few days, receive several separate AirDrop transfers (e.g., a batch of photos Monday, a PDF Wednesday, more photos Friday).
> 2. Later, try to reopen the specific batch received on Wednesday.
> 3. Observe: there is no grouped/received history anywhere in Finder or the AirDrop UI — items sit intermixed in ~/Downloads sorted by name, not by transfer, with no sender/time grouping.

**Expected**
> A browsable, per-transfer history of received AirDrops (sender + timestamp + the files in that transfer), reachable from Finder.

**Actual**
> Received files are dropped into ~/Downloads with no grouping and no history; users re-send files to relocate them.

**Additional notes / proof-of-concept**
> I built a small non-destructive proof-of-concept that reconstructs exactly this from data the OS already writes (`sharingd` quarantine agent + receive-epoch), grouping received files into timestamped batches: https://github.com/jaklabs/airdrop-keep — included to show the grouping is straightforward from existing metadata.

**Attach (optional)**
> A screen recording of steps 1–3, and/or a screenshot of ~/Downloads showing intermixed received files.
