# Physical review packet — not yet executed

Use the matching candidate manifest from
`output/dart-voice-completion/candidate.json`; it identifies the app build, source
commit, native-observed Dart content revision, geometry hashes and print layout.
Build 7 uses **PTC2 revision 2** from Build 6. Its phone installation is now
independently verified; use the PTC2 sheet with it, since old PTC1 sheets cannot
establish alignment. See DEVICE_UPDATE_BUILD_7.md for installation evidence.
Do not collect a candidate result from the wrong app/paper pair.
Before each actual review run, copy the manifest into that run's dated evidence
folder and record the archived copy's path in the CSV. Keep it with the completed
notes; do not rely on the shared candidate path remaining unchanged in later builds.

## Build 7 voice smoke check before the beginner pilot

Use a separate reviewer attempt; keep voice off in both beginner comparison
conditions below. At action 10, choose **Watch in 3D**, return to complete Dart
practice, then explicitly enable **Hands-free** again before final confirmation.
Switching modes already stops voice, so omitting that last enable would not test
the completion boundary. Confirm **I have finished · Save my progress**: listening
and narration should stop. Say **Previous step** / **Restart lesson** and verify
that completed progress stays unchanged. Use the visible **Start again with a
new practice sheet** to reopen action 1; voice should remain off until explicitly
enabled. Also open Setup/Help while listening and verify it stops. Record actual
permission, microphone and progress behavior; Simulator tests do not establish it.

## First: one real complete-course review

1. With the current candidate installed, open the normal home → Paper & craft →
   Classic Dart → Practice the complete Dart. Begin a fresh attempt with a new
   correctly printed A4 sheet, dark mat, even light and a stable phone position.
   Reset saved practice to action 1 using **Previous action** or the finished
   course's **Start again**, rather than resuming another attempt midway.
   Normal practice is sufficient for this qualitative review; no capture launch
   argument, photos, microphone or cloud account is required.
2. Fill the reviewer pseudonym, date, candidate-manifest path, physical attempt
   ID and paper-layout ID in `dart-follow-through-blank.csv`. Keep every initial
   status **not_tested** until a person actually performs the action.
3. Physically perform all ten actions. For each, choose `observed_pass`,
   `needs_revision` or `cannot_judge` and describe what actually happened. Compare
   the written action, the moving layer/direction, the resting result and help.
   A successful animation or an author's source-code check is not observed_pass.
4. Preserve ambiguity, especially crease/hidden-layer claims. Record a proposed
   correction, change the candidate, then perform an explicit recheck; keep the
   original observation. An amended source revision needs its own archived
   manifest and a new CSV/review record with its own date and attempt ID. Use
   `recheck_status` only to link that follow-up, not to overwrite earlier results.
5. Keep natural-paper alignment, printed-paper checks and complete tutorial
   review as separate results. A manual pass does not approve camera accuracy.
   Use PHYSICAL_VALIDATION.md for movement, loss/recovery and negative examples.

Once actual review changes are resolved, freeze that candidate before the
beginner pilot. The CSV provided here contains no approved content or results.

## Independent image labels

Explicit camera samples require a Debug launch with `--practice-validation`;
normal launch deliberately does not store images. See LOCAL_VALIDATION_CAPTURE.md
for the user-triggered save and transfer. Start flat-sheet measurements at
**action 2 after reopening**, because the current capture UI has actions 1–10,
not an export action 0.

Open `tools/validation_annotator/index.html` and select a sample's original
`sample.json` and exact `image.png`. The tool hides predictions and validates
their dimensions/hash. Choose the visible label independently. For flat state 2,
optional original-sheet corner clicks supply held-out geometry and a bottom-edge
full-width reference; folded or hidden corners must not receive invented source
coordinates. Export JSONL explicitly and evaluate it with
`scripts/evaluate_practice_validation.py`. Label disagreements need human review.
Synthetic test exports remain synthetic and cannot satisfy the physical gate.

## Then: exploratory beginner comparison

Use about ten beginners, each in **one** condition to avoid learning the same
fold on a repeat. Assign 5 to the existing 3D/text reference and 5 to guided Dart
practice before sessions, balancing prior folding experience where feasible.
This small pilot compares the complete workflows; it cannot isolate a causal
benefit of computer vision or establish a population learning percentage.

Give everyone the same candidate/device, PTC2 A4 material, mat, phone stand and
neutral setup explanation. Preflight camera access before timing. Voice is off
in both conditions for this first comparison; assess voice separately. Briefly
explain anonymous timing/notes and obtain the participant's agreement; ask
separately before any photographs. Participation can stop at any time.

Before each participant, the facilitator must reset/check **both** persistent
3D lesson and complete guided-practice progress to their starting action with no
completion recorded. A fresh paper sheet alone does not clear saved app state.
In studio, use the step list's initial flat-sheet entry; in guided practice use
**Previous action** until action 1 (or its completed-course **Start again**).
Verify the saved beginning after returning to the landing page. Record this
preflight in observer notes; do not begin timing a resumed later action.

Suggested neutral brief: “Use the tutorial to make the paper plane. You may
pause, replay or use its help. Tell me when you are finished or want to stop.”

- **Start:** participant taps the assigned tutorial entry from the prepared
  Classic Dart landing (3D lesson or complete guided practice). Include normal
  navigation, registration and help overhead in elapsed time; do not substitute
  camera-frame age for participant time.
- **End:** learner declares completion, withdraws, or reaches a predeclared
  **15-minute exploratory stopping limit**. Record the actual reason and time;
  a timeout is not completion.
- **Help:** on the participant's first request, point to built-in help without
  explaining the fold. Count each opening of the action-help panel or its 3D
  replay as one `app_help_uses` event, including repeat openings; keep simple
  pause/play interactions out of this count. Give human procedural help only on
  a further explicit request,
  count each intervention and record its content. Do not fold the object for the
  participant and then count it as their independent completion.
- **Result:** separately record learner-declared completion and an independent
  reviewer's `visible_match` / `needs_adjustment` / `cannot_judge` final result.
  Compare visible wing pairing and body-below arrangement; hidden fold order,
  flight performance and learning transfer are not established by that view.
  Record the final reviewer pseudonym and whether they knew the condition in
  `observer_notes`. Hide the assigned condition where practical; do not call
  the result blinded if the reviewer actually knew the assignment.

Use `beginner-results-blank.csv` plus actual observer notes. Rows have no assigned
outcome, condition or time. Preserve unfinished attempts; do not replace blank
values with zero or invent percentages from this preparation packet.
