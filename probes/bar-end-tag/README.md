# bar-end-tag

Throwaway probe for the map ticket "Bar-end tag mount": print sheets for the tagged bar the XR benchmark needs.

- `bar-end-tags.pdf`: three US Letter pages. Print at **100% scale, fit-to-page off**.
  1. `tag36h11` ID 0, 90 mm printed (72 mm detection edge), on a 100 mm carrier.
  2. `tagStandard41h12` ID 0, 90 mm printed (50 mm detection edge), the comparison arm.
  3. Fallback: two `tag36h11` ID 0 at 35 mm printed (28 mm detection edge), inside a 50 mm circle.
- `make_sheets.py`: regenerates the PDF from `tags/` (`python3 -I make_sheets.py`, standard library only).
- `tags/`: one-pixel-per-cell tag images from
  [AprilRobotics/apriltag-imgs](https://github.com/AprilRobotics/apriltag-imgs), BSD-2-Clause.

## Build checklist

Print

1. Print all three pages on matte paper at 100% scale. Inkjet: let the ink dry before handling.
2. Measure the scale line on each page. It must be 100 mm. If it is off by more than 0.5 mm, fix the print settings and reprint.
3. With calipers, measure the detection edge of each tag in both directions and write the values down. 36h11: the outer edge of the black square (nominal 72 mm; fallback 28 mm). 41h12: the inner edge of the black ring (nominal 50 mm).

Carrier

4. Cut two rigid, flat 100 mm squares (3 mm plywood, acrylic, foam PVC, or stiff aluminium composite). Cardboard is too soft.
5. Cut each big tag on the grey square and glue it flat to a carrier with spray adhesive or a glue stick. No bubbles, no curl, no glossy tape or laminate over the tag.
6. Carry the four black centre ticks round onto the back of the carrier and join them to mark its centre.

End cap

7. Look at the sleeve end of each bar the lab will use, including the trap bar. Note for each: flat steel face, recessed end cap, or hollow bore, and the sleeve diameter.
8. Fix a seat to the back of the carrier, centred on the mark, that holds the carrier square to the bar axis:
   - flat steel end face: two or three strong magnets (for example 20 mm neodymium discs);
   - otherwise a cup that slips over the sleeve end (a 2 inch / 50 mm pipe cap or a printed cup) with a thumbscrew or a tight friction fit.
9. Fit it after the plates and collar. Check by eye from the side that the carrier is perpendicular to the bar, and from the end that the tag centre sits on the bar axis.

Fallback

10. Cut one 35 mm tag on the grey circle and stick it flat on the sleeve end face of one bar.

Check

11. Spin the sleeve by hand with the cap on. The tag should spin in place; note any visible wobble or circling of its centre.
12. Do a few reps of each lift with a light load. Note whether the cap stays seated and centred, and anything that knocks it.
13. Photograph each bar end with and without the cap. No people in the photos.

## Report back

- Measured detection edges (36h11 90 mm, 41h12 90 mm, 36h11 35 mm).
- Carrier material and how the cap seats.
- For each bar: end-face geometry, sleeve diameter, does the cap fit.
- Wobble when the sleeve spins, and anything that came loose during reps.
- Where the photos are.
