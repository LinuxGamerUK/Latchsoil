# 2026-10-18 — milestone 2, the body keeps score

Played: milestone 2. The contract was frozen first (`bc32467`), the code landed in `368f458`, and this note follows it.

Where: **review frames rendered on the build host**, software Vulkan under Xvfb, through `scripts/render.sh`, and every picture was produced by driving the real sim with its own rows printed beside it. **No hand has played milestone 2.** This is a review, and it says so. The frames are kept beside the project note in the vault; the repository carries the driver that reproduces them.

## What the frames establish

**A wound bleeds, and the sim's numbers are the ones drawn.** A left leg was set to `bleeding` 1.0 — no rule wounds anybody until milestone 5, so the driver sets it through the save, the same seam the harness uses and declares in its own words. Over 720 ticks the person's health fell 1.0 to **0.9000**, exactly 720 × 1/7200, and the same region's infection rose to **0.025**, exactly 720 × 1/28800. The HUD reads `wounds: left leg bleeding, infected, untreated`, which is the "UI clock" the art doc asks for beside the decal and the limp.

**The wound now reads as a wound.** A red mark sits on the left leg and the leg leaves the body and ends in a dark foot, rather than being a chunk on the ground plane. **The limp reads:** the body is tilted with a trailing foot outside the rings. **The hurt flag reads** and sits clear of the job label. All three verified at 4 m and at ortho 6, by the agent that drew them and independently by me. Before this pass none of the three read at all — the mark was invisible on the body and the person stood idle.

**Sleeping reads as sleeping.** A body lying on a bedroll with the label `rest`, beside a standing neighbour: a different silhouette, not a different tint.

## What this milestone does not deliver: cold

Temperature does **not** read off the body at either distance. Three mechanisms were tried, and the diagnosis is worth more than the attempts:

- A blue ground ring read as cold at 4 m, but was confusable with the selection ring.
- Replacing it with a white post beside the person made two readers call it a stake or a blueprint object, and at holding zoom it read as nothing at all. That one was a regression, and it was mine: a cue that reads beats a cue that is tidy, and confusion with another ring should be solved by shape or motion rather than by dropping the colour that carried the meaning.
- Tinting the body ice-blue fails for a reason worth keeping: **these bodies already carry blue in their palette** — the Harth accent — so a blue person looks like a person, not a cold one. At 4 m a reader said the colour "appears to be the character's sprite colour rather than an indicator of cold"; at holding zoom the figures are clearly distinguishable from the props, but "there is no obvious visual cue" for cold.
- The shiver now in the code (0.30 m lateral, 0.12 m jitter, 0.09 m bob, ±16° roll, a 6-frame period) is a *motion* cue, so a still frame cannot show it at all. Nobody has watched it move.

What survives is the HUD number (`warmth 0.63`). The information is not hidden; it is simply not on the body, and the art doc's readability checklist asks for the body to say it.

## What a person still has to judge

- **Whether the shiver reads in motion.** That needs eyes on a running game, not a frame, and it is the cheapest thing left to test.
- **Whether the limp reads at walking pace** rather than as a stagger. The sim refused the walk frame — the wounded person stood at tick 6799, inside the night range — so the only limp seen is a standing drag. No frame shows a wounded person walking.
- **No frame shows a heavy infection or a bandage either:** infection was 0.025 and `bandaged` false in every frame. What is drawn is bleeding, low infection, and untreated.
- **Whether a night in the open costing a tenth of a person's health feels fair or punitive.** That is balance, and only play answers it.

## Owed

A hand on it: bandage someone and watch the limp walk, sleep a night through beside a fire, and see whether the shiver reads while it moves. And an art decision on the cold cue — the honest candidates are a palette-independent one (visible breath, or a desaturated pale-grey cast rather than blue) or accepting that temperature stays a HUD fact at holding zoom.
