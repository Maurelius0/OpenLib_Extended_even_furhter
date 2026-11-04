# Reader test v15

Adds double-tap zoom to the existing picture viewer, without adding controls or
changing the approved reader layout. Double-tapping a fitted picture animates
to 2.5× around the tapped position. Double-tapping a zoomed picture (including
one zoomed/panned with pinch gestures) returns it to its original fitted view.
Pinch zoom retains the existing 1×–8× range. Zoomed dragging pans rather than
closing; a short downward swipe after returning to fit still closes with the
existing slide/fade animation.

The zoom uses the existing transformation controller and an idle-until-used
180ms animation controller. New touch input stops the animation immediately,
so zoom animation and manual pinch/pan never write the transformation together.
The new animation honors the system's reduced-motion setting. No dependencies,
network calls, background work or native changes were added.

Validation: 84 reader regressions passed, including actual double-tap gestures
on SVG and raster images, off-center focal point preservation with a visible
caption, return to fit from a panned zoom, pan-versus-dismiss behavior,
interruption by new input, safe Back cleanup and reduced motion. Existing
pinch/multitouch, swipe/fade, book controls, fonts, links, publisher formatting,
PDF, library and inactivity tests also passed. Targeted Dart analysis is clean.

The APK uses the existing Reader Test signing key and retains the previous
native code/assets; only the Dart AOT library changes. Signature and 16KB APK
alignment are checked. Physical Pixel/GrapheneOS gesture timing remains a
device check. Install over the existing app without uninstalling.
