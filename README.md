# SketchUp Geometry Decimator

A SketchUp extension that:
- Simplifies dense geometry with a strength slider.
- Provides before/after preview toggle.
- Displays original, reduced, and final (watertight cleanup) face counts.
- Tracks activity in a UI log.
- Uses a Python helper for mesh math processing.

## Install
1. Zip this repo contents and install as a SketchUp extension, or copy files to your SketchUp Plugins folder.
2. Ensure `python3` is available on your system PATH.
3. Restart SketchUp.

## Use
1. Select a **Group** or **Component Instance**.
2. Open `Plugins > Geometry Decimator > Open Decimator`.
3. Click **Analyze Selection**.
4. Set simplification strength and click **Run Decimation**.
5. Use **Toggle Before/After Preview**.
6. Click **Apply Result** to commit changes.

## Notes
- The watertight pass is a lightweight cleanup heuristic and may need manual repair for difficult topology.
