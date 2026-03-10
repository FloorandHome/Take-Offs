# Building Plan Room Mapper

This program reads a building plan from JSON or PDF, maps each room on a simple top-view grid, and lists room dimensions.

## Plan format

The program expects plan data in one of these forms:

- A `.json` file containing the plan payload
- A text-based `.pdf` containing the same JSON payload
- A scanned/image `.pdf` that OCR can turn into labeled room text such as `Unit: m` and `Name: Living X: 0 Y: 0 Width: 6 Height: 4`

Example JSON payload:

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

## PDF and OCR support

- Text PDFs: the program searches for embedded plan JSON or labeled room data
- Scanned/image PDFs: the program falls back to OCR when local tools are available
- OCR tools required for scanned PDFs:
  - `tesseract`
  - `pdftoppm` or `magick`

If OCR tools are not installed, scanned/image PDFs will fail with a helpful error.

## Run

```bash
python3 plan_reader.py sample_plan.json
python3 plan_reader.py plan.pdf
```

## Test

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```
