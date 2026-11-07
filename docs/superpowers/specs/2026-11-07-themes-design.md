# bar-tab — Selectable designs (issue #4)

Status: draft for maintainer review, 2026-11-07. Main spec: `2026-11-02-bar-tab-design.md`.

## 1. Intent

The tablet app works but looks purely functional. Issue #4 gives it more character without
slowing down the job it exists for: recording who drank what. The maintainer wants several
designs to choose from instead of one new look. Today's look stays as **"Standard"**; two new
designs are added: **"Kreidetafel"** (chalkboard) and **"Bierdeckel"** (beer coasters).

The maintainer describes the goal plainly: easy to use, looks good, people leave the tablet with
a positive impression — but bar-tab is a data-entry tool first. Every design decision is judged
by that order.

The new designs also bring a **new arrangement** of the drink selection: drinks of one group
form one visually connected block (like the brand clusters on a self-service drink dispenser),
instead of today's one-row-per-group grid. Only the idea is borrowed; no brand look is copied.

## 2. Goals, non-goals, anti-goals

**Goals**
- Three designs: Standard (unchanged), Kreidetafel, Bierdeckel.
- The design is chosen **per tablet** in the admin area and applies immediately.
- In both new designs, groups are visually connected blocks, and the person's favourites (the
  quick bar, §4.2 of the main spec) stand out clearly: larger, own colour, own place.
- Every design copes with any number of groups, drinks and persons without manual layout work.
- Long names stay readable in every design.

**Non-goals**
- No change to any flow: one tap on a drink books (multi-tap, quantity sheet from the third
  tap, 5 s auto-booking, "Fertig", undo window, idle returns — all as today).
- No sub-groups ("families" such as Cola/Limo/Eistee inside a group). Considered and dropped by
  the maintainer.
- No hand-made favourites, no per-person designs, no server-wide design setting.
- Which groups exist (e.g. whether "Wasser" is its own group) is data, configured later in the
  admin area — not part of this work.

**Anti-goals** (would make this a failure even if it technically works)
- A booking taking more than two taps in the common case.
- Jank on the target tablet (Rockchip rk3399, Android 11).
- Text that is cut off or unreadable (e.g. a long name dissolving into a coaster's rim).
- Club-specific colours, names or logos in code.

## 3. Constraints

- Everything in the main spec's engineering rules applies (TDD, l10n `.arb` strings only, clock
  wrapper, no real data in the repo, `app/tool/check.sh` clean).
- Landscape tablet, UI scaled to a 1280 design width (`UiScale`), large touch targets. A coaster
  or tile is never smaller than ~44 design px across.
- **Performance:** animations must be cheap (opacity/transform of a few widgets). No live blur
  (`BackdropFilter`). Textures (chalkboard grain, green counter speckle) are drawn once — cached
  painter or a small bundled image — not recomputed per frame.
- **Offline kiosk:** fonts are bundled as assets (no runtime font download). New fonts must be
  open-licensed (OFL); the mockups used *Caveat* (handwriting) for Kreidetafel and
  *Alfa Slab One* + *Barlow Condensed* for Bierdeckel. Standard keeps *Archivo*.
- **Maximum lengths** (maintainer, 2026-11-07): person / collective account name **20**, drink
  **24**, drink group **16**, price tier **16** characters. Today no endpoint creates or renames
  these entities, so enforcement belongs to the work that adds those paths: the admin master-data
  screens and endpoints (milestone 3) and the legacy import, which reports longer values
  (milestone 5). Recorded in the main spec for those milestones. The app does not rely on the
  limit: a longer name is still rendered (multi-word wrap; a single word is shrunk to the minimum
  size and, if still too long, cut with an ellipsis) instead of breaking the layout.

## 4. Decisions (maintainer, 2026-11-07)

### 4.1 Choosing a design
- Admin home gets a "Design" choice with the three options; the choice is stored locally on the
  tablet (existing app config store) and applies at once, without restart. Default: Standard.
- Setup, admin screens and the sync indicator only take over the design's **colours and fonts**;
  they get no design-specific layout.

### 4.2 Standard
Today's look and layout, unchanged (bottle green, coloured rails, quick bar row on top).

### 4.3 Kreidetafel (chalkboard)
Look: slate board (`#3a403c` → `#232724`, faint diagonal grain) in a wooden frame (`#7a5534`),
handwritten chalk lettering (`#f4f1e8`), prices and highlights in yellow chalk (`#f7d774`),
tiles as hand-drawn dashed chalk boxes with slightly irregular corners.

- **Drink selection:** each group is a chalk-framed **field** with the group name as an
  underlined heading; drinks are chalk boxes "name … price". Fields are laid out as columns whose
  share of the width follows their number of drinks; a large group uses two box columns inside
  its field; small groups may stack in one column. When a field has more drinks than fit, that
  field scrolls on its own (same idea as the name list today).
- **Favourites:** a separate board on the left titled "Für dich" with ★ decorations, a yellow
  double frame, hung slightly crooked (≈ −1°), with the four drinks in large type (about twice
  the normal size).
- **Name list:** heading "Wer trinkt?", collective accounts in yellow chalk on top, one column
  per price tier with its name as underlined heading, persons as chalk boxes, three per row,
  alphabetical; overflow as today (shrink, then scroll per column). Boxes are as high as the
  longest column allows (up to 100 px at 1280×720) so the board is filled; three per row down to
  60 px, then four per row down to 50 px, then the columns scroll. One name size per column; a
  name much longer than the others (fitted size below 80 % of the column's median) shrinks alone.
- **Undo banner:** a paper note pinned with a red pin, slightly rotated, with the "Rückgängig"
  button drawn as a chalk box and a line that drains over the undo window.
- **Quantity sheet:** a small slate board in a wooden frame over the dimmed selection; drink name,
  quantity in large yellow chalk, keys as hand-drawn chalk circles (incl. "Kasten" in yellow),
  "Buchen" and "Weitere Getränke" as chalk buttons.
- **Screensaver:** near-black board; a chalk-drawn beer glass with "Zum Buchen antippen" slowly
  moves between positions.

### 4.4 Bierdeckel (beer coasters)
Look: **green bar counter** (dark green `#2f5a47` → `#17322a` with a fine speckle) — the brown
wood was rejected; coasters cream (`#f3e7cf`) with a coloured ring; slab-serif names; accent
`#7a1f1f` (dark red) and gold rim `#d9a441` for highlighted coasters.

- **Drink selection — rings:** each group is a large hub coaster in the group's colour showing
  the group name, with the drinks as coasters in rings around it.
  - All coasters have one **fixed size**; the app knows 2–3 size steps.
  - The inner ring is filled first; when it is full, a second ring starts around it, then a third.
  - **A new ring is opened only when at least 3 coasters go into it.** Until then the previous
    ring takes the extra coasters: it first gets a slightly larger radius; if the screen space
    does not allow that, its coasters drop one size step and move closer together. Single
    coasters alone in an outer ring never appear.
  - Coasters in a ring are spread evenly around it.
  - If all groups do not fit at a size step, every coaster drops one step together; if even the
    smallest step does not fit, the selection area scrolls.
  - Group blocks are arranged to use the available area (e.g. two small groups stacked in a
    column next to a large one).
- **Favourites:** four large coasters with a gold rim and a small ★ on a silver serving tray
  ("Dein Tablett") on the left, each slightly rotated.
- **Name list:** heading "Wer trinkt?", collective accounts as large gold-rimmed coasters on
  top, one column per price tier (tier colour as a dot next to the heading and as the persons'
  ring colour), persons as coasters, five per row, some slightly rotated; overflow as today.
  Coasters are as large as fit (up to 150 px, kept below the 120 px collective coasters); five
  per row, or four or three when that makes them larger, so a short list fills the height. Below
  88 px the columns scroll at 88 px: a single word of 20 characters may cross the rim but is not
  cut.
- **Undo banner:** a till receipt (monospace text, zigzag bottom edge) that slides in from the
  top, with a dark-red "Rückgängig" button and a draining line.
- **Quantity sheet:** a large coaster in the middle carries drink name, quantity and the keypad
  (small round keys, "Kasten" in the accent colour); "Buchen" and "Weitere Getränke" sit next to
  it so the coaster stays round.
- **Screensaver:** dimmed counter; one coaster with "Zum Buchen antippen" slowly moves and turns.
- **Text on coasters:**
  - Names of **several words** wrap at spaces or hyphens onto up to three lines inside the
    coaster, shrinking down to a minimum size.
  - A **single long word** keeps one line and may extend beyond the coaster's rim.
  - **Every** name on a coaster gets a sharp outline in the coaster colour (text drawn twice:
    stroke behind fill), so text that crosses the rim or the green counter stays readable and
    all coasters look alike whether their name overflows or not.

## 5. Calls made by Claude (please check)
- Hub and drink-ring colours use the colour configured for each drink group (data). Price tiers
  have no colour in the data; their colours keep coming from the existing index palette
  (`tierColor`), each design supplying its own palette. The theme supplies coaster, counter and
  accent colours.
- Overflow only ever scrolls **vertically**, never sideways (consistent with the name list).
  Kreidetafel: when the fields do not fit side by side even with stacking, they wrap into a
  further row and the selection area scrolls vertically; a single over-full field scrolls on its
  own. Bierdeckel: after the smallest size step, the selection area scrolls vertically. No group
  is ever hidden.
- The ring rule works with circumference: a ring holds as many coasters as fit with a fixed gap;
  "slightly larger radius" means up to the radius at which the extra coasters fit, limited by
  the space the group block has.
- Kreidetafel field widths follow drink counts with a minimum width so a field with one drink
  stays readable.
- The favourites column is used in both new designs even when a person has fewer than four
  favourites (fewer items, larger spacing); with none it is hidden, as today's quick bar.
- The order bar, header (person, running total, "Andere Person") and sync indicator keep their
  content and position and only take the design's colours and fonts.
- Design-specific strings ("Für dich", "Dein Tablett", "Design", the design names) go into
  `app_de.arb`.
- Mockups live only in the git-ignored `.superpowers/brainstorm/` folder; this document is the
  record.

## 6. Left to the builder
How designs are implemented (e.g. one theme object per design plus design-specific widgets for
the drink selection, name list, undo banner, quantity sheet and screensaver), exact sizes, font
sizes and spacing, texture technique, animation details within the performance constraint, the
exact ring capacity maths and size steps, test strategy for layouts (the ring/field layout rules
should be pure, unit-tested functions).

## 7. Acceptance criteria
- [ ] Admin can switch between Standard, Kreidetafel and Bierdeckel; the choice survives a
      restart and applies immediately.
- [ ] Standard looks and behaves exactly as before (existing widget tests unchanged).
- [ ] In both new designs, booking flows behave exactly as in Standard (same behaviour tests run
      against each design).
- [ ] Ring layout rule tested: fill order, "new ring only with ≥ 3", widen-then-shrink, shared
      size step, scroll fallback.
- [ ] Kreidetafel field layout tested for small and large groups and many groups.
- [ ] Long single words and multi-word names render as specified on coasters.
- [ ] Over-long names (beyond the maximum lengths) still render without breaking the layout.
- [ ] Verified on the target tablet (release build): smooth, readable, intuitive.
