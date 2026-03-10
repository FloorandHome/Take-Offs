# Building Plan Room Mapper

This program reads a building plan from JSON, maps each room on a simple top-view grid, and lists room dimensions.

## Plan format

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

## Run

```bash
python3 plan_reader.py sample_plan.json
```

## Test

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```
