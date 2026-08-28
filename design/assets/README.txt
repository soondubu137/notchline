NOTCHLINE — LOGO ASSETS
=======================

Colours
  Codex blue        #6CB4FF   (upper-left field)
  Claude terracotta #D97757   (lower-right field)
  Seam / ink        #121212
  Reversed text     #FFFFFF

01-mark/            Square mark, diagonal seam as negative space.
                    notchline-mark.svg (vector, scales freely)
                    notchline-mark-1024 / 512 / 256 .png

02-horizontal/      Horizontal lockup — wordmark cap height = mark height.
                    -transparent.png  seam voided, dark wordmark, alpha background
                    -white.png        seam voided, dark wordmark on #FFFFFF
                    -black.png        seam inked, white wordmark on #000000

03-stacked/         Stacked lockup — wordmark width = mark width.
                    same three grounds as above.

04-macos-icon/      App icon on the black squircle (22.4% corner radius).
                    notchline-icon-macos.svg
                    notchline-icon-1024 / 512 / 256 / 128 .png

matrix-states/      The collapsed overlay's status matrix, one animated SVG
                    per state. 4x4, drawn in Claude Code's terracotta over
                    #21120D; Codex runs the same four patterns in its own
                    blue, because the pattern says the state and the hue says
                    the product.
                    notchline-running-radar.svg           1200ms, 36 frames
                    notchline-approval-double-knock.svg   1200ms, 36 frames
                    notchline-input-advance.svg            800ms, 24 frames
                    notchline-completed-lull.svg          2000ms, 60 frames
                    Each file writes one waveform sixteen times at sixteen
                    offsets. The app holds the waveform once and computes the
                    offsets: MatrixTrack in NotchStatusMatrix.swift, spelled
                    out in docs/figma-design.md section 4.1.
                    loaders-wtf-import.js is where the four came from: paste it
                    into the console at loaders.wtf to get the whole candidate
                    sheet back, these four among them.

Typeface
  Wordmark is set in Encode Sans, Medium (500), tracked +1.2% in the
  horizontal lockup. Free via Google Fonts.
  The lockup PNGs are rendered at 3x (wordmark drawn at 120px / 200px
  design size) so they hold up at any normal placement size. If you need
  vector lockups, set the word in Encode Sans Medium and convert to
  outlines, then pair it with 01-mark/notchline-mark.svg using the
  alignment rules above.
