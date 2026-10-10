Five original options for Only test ($TEST), each an opaque 1024×1024 PNG. The [creator reference](https://fxumiqjngmabtgvruvka.supabase.co/storage/v1/object/public/forum-attachments/posts/mv2zn9kb-aw7l6q.webp) contains muted cool-gray text on black and no illustrated character; these variations preserve that palette and develop a test-tube subject from the name.

1. [logo-1.png](logo-1.png) — Mascot: a deadpan silver test-tube character with chunky feet and half-lidded eyes.
2. [logo-2.png](logo-2.png) — Minimal icon: one bold silver test-tube silhouette on black; selected for the wallet logo.
3. [logo-3.png](logo-3.png) — Lettermark: the ticker TEST in a compact, heavy two-row geometric arrangement; the only option containing letters.
4. [logo-4.png](logo-4.png) — Minted emblem: a satin silver coin with a deeply inset test-tube symbol.
5. [logo-5.png](logo-5.png) — Meme illustration: an exuberant test-tube character with a large connected splash and comic expression.

All artwork was drawn by the built-in `image_gen` image-generation tool, using the supplied reference. **Five drafts were generated, one per approach; all five were retained, with no rejected drafts or redraws.** No logo was drawn with code. FFmpeg only resized the generated images to the required PNG dimensions and made disposable inspection previews. The [exact prompt set](PROMPTS.md) is included.

`../artifacts/logo.png` is a byte-for-byte copy of option 2. It was inspected as an actual 32-pixel circle on light and dark backgrounds: the single test tube remains readable, the black background fills the square, and there are no letters, numbers, frame or border. All five options were also inspected at 64 pixels on light and dark backgrounds.

Inspection previews: [five options at 64 pixels](preview-64px.png) (options 1–5 from left to right, light above dark), and [selected mark as a 32-pixel circle](../artifacts/logo-32px-review.png). These are display checks, not additional logo drafts.

The other four options remain deliverables, but were not selected for the 32-pixel wallet artifact: the mascot has smaller facial details, the lettermark contains letters, the minted badge has a rim, and the meme illustration is busier at that size. Option 2 best meets the single-mark requirement.
