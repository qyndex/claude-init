# Restore approved two-page discovery observation bound

Isolated base3cd647ab25af05549ad5709c117c888549996978. No shared candidate changes.
plans/active/014-authenticated-receipt-recovery.md:T285 explicitly requires at most
two source pages/200 new identities per observation. The prior three-page head+
older-overlap source passed its recorded tests but violated that plan. Those proofs
and review artifacts remain unchanged; they are not compliant acceptance evidence.

Correction: primary page1 already observes head. For later odd primary pages, observe
head1 only and retain older-overlap cursor unchanged. For even pages, fetch the saved
older-overlap page unless it duplicates primary, then advance the overlap cursor only
when actually fetched. Thus at most2distinct pages/200rows are observed, and head is
revisited within2advancing observations while older overlap continues. Short/empty
wrap, immutable identity deduplication, schema and existing global bounds unchanged.
No source page/identity budget increase or history-completeness claim.

Actual final-test RED against immutable original3cd source in a separate baseline
clone exits1 at `observation exceeds two distinct source pages` (red.log). A prior
selector assertion diagnostic and initial budget reproduction are retained separately.
The exact final test file was copied to that baseline clone without production edits;
no old source/proof histories were rewritten.

GREEN deep-listing real-Git control: new head arrives after odd-page observation;
next even observation fetches older overlap, following odd observes new head. Every
call has at most2distinct source pages, cursor stays unchanged on head-only calls and
advances on actual older fetches. Wide real-Git control: two actual100-row source
pages atomically retain exactly200new identities with coverage false. After the first
100-watch suffix, the fixture must use actual bounded advance_origin before resuming;
its initial missing-origin prerequisite attempt failed the existing bootstrap tree
window, and was not a product RED/PASS or reason to loosen that window.

Final focused commands are head-deep and two-page-cap; unaffected backfill/review/
producer loops were not repeated. Existing bounded discovery regression and structural
validation outputs are retained; final exits are recorded in verification.json.
No native calls, new model calls, large producer rerun, activation or task closure.
Typed own-budget changes remain as in3cd; lower-layer proofcatch limitations unchanged.
Parent owns exact integration and focused independent review.
