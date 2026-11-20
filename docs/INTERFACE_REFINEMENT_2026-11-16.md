# Everyday interface refinement

## Design decision

Audience: a learner looking between a physical object and a phone. The page's
job is to make the current movement easy to inspect, then let the learner
explicitly confirm their own attempt.

Keep the existing quiet, green brand. Tokens: paper `#F7F9F9`, ink `#212926`,
forest `#244A40`, muted `#616E69`, divider `#E6E9E7`, white `#FFFFFF`.
Use the native SF system family: restrained semibold titles, regular body,
monospaced digits for movement percentage and step position. Scale meaningful
text with Dynamic Type. No decorative counters or promotional copy.

The signature remains the real, interactive teaching model. Keep secondary
explanation behind an explicit disclosure; group Play and the draggable
timeline into one row. The completion button continues to require the learner's
confirmation, and existing progress/AR behavior is preserved.

Portrait: course header → model → compact action panel. Landscape: the same
renderer on the left, scrollable action panel on the right. Large text can
scroll the action panel without hiding the model entirely.

Home: object-first cards retain Origami first, add meaningful saved progress,
and lower the visual priority of setup. No new carousel, badges for fictitious
mastery, or additional account system.

This follows Apple's [layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout)
on progressive disclosure and adapting layout to text size and orientation.
The existing brand is retained deliberately; a new visual theme would distract
from the learning flow the user has already accepted.

## Verification

Local candidate: **1.0 (33)** in the prototype namespace. No App Store or
TestFlight upload is part of this change.

Implemented in the existing home and everyday player:

- Course tiles expose the saved current action; the bar counts only actions the
  learner explicitly confirmed. Origami remains the first course entry.
- Setup is a quiet helper beside Explore origami, rather than a card above the
  main lesson.
- Playback, timeline and percentage share one row. The title's chevron opens
  the detailed instruction; Help retains the complete instruction as well.
- A measured, scrollable action panel preserves space for the model at large
  text sizes. iPad landscape places controls beside the same renderer.
- Main text scales; muted small text now has approximately 5.05:1 contrast on
  the paper background. Help controls use the same green accent.
- Confirmation behavior, saved steps and AR alignment behavior are unchanged.
  The Previous control's accessibility hint describes the existing redo or
  preview behavior.

### Results

Seven distinct Simulator UI cases passed, with the compact-layout and tablet
cases also rechecked after waiting for the disclosure to settle:

| Scope | Result | Receipt under `output/interface-refinement-20261116/` |
| --- | --- | --- |
| iPhone 17 Pro Max, iOS 26.5: six cases | 6 passed, 0 failed, 0 skipped | `Phone.xcresult`, `phone-summary.json` |
| Final iPhone disclosure/control bounds and saved progress | 1 passed, 0 failed | `PhoneSettled.xcresult`, `phone-settled-summary.json` |
| Final iPad portrait/landscape, paused model, instruction/control separation | 1 passed, 0 failed | `TabletAfterRestart.xcresult`, `tablet-after-restart-summary.json` |

Coverage includes all five everyday courses' playback/scrubbing; labeled AR
layout switching without camera fixtures being mistaken for real tracking;
Classic Dart first fold and persisted resume; Origami filter/setup navigation;
large Dynamic Type instruction scrolling; and expanded/collapsed instructions
without changing saved practice. These checks do not re-certify every physical
action or every course's teaching content.

The intermediate `TabletSettled.xcresult` failed because the Simulator did not
enter landscape after the orientation command. Restarting only the test iPad
restored rotation; the unchanged app and test then passed. Final geometry
records a 1376 × 1032 app, a left-hand model viewport ending at x=976 and the
timeline starting at x=1056. The earlier iPad screenshot raster had a direction
mismatch; retain geometry receipts and do not use that raster as device proof.

Screenshots were inspected for the home, compact and expanded towel lesson,
maximum text-size controls, and tablet layout. Final screenshots live in
`phone-settled-screens/` and `tablet-final-screens/`; `phone-screens/` also holds
the large-text and five-course images. `git diff --check` passes.

Camera tracking, physical alignment, hand occlusion and hands-free voice still
need device acceptance. No physical iPhone installation or publication was
performed during this design pass.

## Next useful refinements

1. Replace the remaining flat catalog illustrations with consistent previews
   of the actual course models, so the card and opened lesson look related.
2. Improve cloth thickness, folded edges and surface cues while keeping the
   moving part easy to read; retain the distinction from physical cloth simulation.
3. Observe one real first-time learner completing a towel course before
   changing the AR alignment menu or adding more hints. Confirm that they find
   the instruction disclosure and understand that Next records their attempt.

These are follow-up opportunities, not features included in this candidate.

The first two follow-ups subsequently received a local Build 34 implementation:
real-model catalog portraits and thin closed cloth edges. See
`EVERYDAY_MATERIAL_REFINEMENT_2026-11-16.md` for its separate test receipts and
remaining physical-device gate.
