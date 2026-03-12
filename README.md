# Floor Plan Takeoff

This repo now includes two ways to work with floor plans:

- `index.html`: a browser-based room takeoff page for uploading a PDF floor plan, calibrating scale, tracing rooms, and listing dimensions by room plus total area.
- `plan_reader.py`: the original JSON-based CLI mapper.

## Web page

Open [index.html](/C:/Users/MegBrewington/Documents/GitHub/Take-Offs/index.html) in a browser, or serve the folder with a simple static server if your browser blocks local PDF rendering.

### Web workflow

1. Upload a `.pdf` floor plan.
2. Click `Calibrate scale`.
3. Click two points on the plan with a known real-world distance.
4. Enter that distance.
5. Click `Draw room` and drag rectangles over each room.

The page renders the first PDF page, overlays the mapped rooms, and updates the room table and total area live.

## CLI plan format

```json
{
  "unit": "m",
  "rooms": [
    {"name": "Living", "x": 0, "y": 0, "width": 6, "height": 4}
  ]
}
```

- `x`, `y`: room origin coordinates (integers)
- `width`, `height`: positive integer dimensions
- Rooms cannot overlap

## CLI run

```bash
python3 plan_reader.py sample_plan.json
```

## CLI tests

```bash
python3 -m unittest discover -s tests -p "test_*.py"
```
