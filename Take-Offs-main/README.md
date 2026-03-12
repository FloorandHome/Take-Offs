# Building Plan Room Mapper

This project now includes a native PowerShell implementation for Windows 10 and Windows 11 in `plan_reader.ps1`, plus a small upload UI in `plan_reader_ui.ps1`. It reads a building plan from JSON or PDF, maps each room on a simple top-view grid, and lists room dimensions.

## Plan format

The program expects plan data in one of these forms:

- A `.json` file containing the plan payload
- A text-based `.pdf` containing the same JSON payload
- A scanned/image `.pdf` that OCR can turn into labeled room text such as `Unit: m` and `Name: Living X: 0 Y: 0 Width: 6 Length: 4`

Example JSON payload:

```json
{
  "unit": "m",
  "rooms": [
    {"name": "Living", "x": 0, "y": 0, "width": 6, "length": 4}
  ]
}
```

- `x`, `y`: room origin coordinates (integers)
- `width`, `length`: positive integer dimensions
- Rooms cannot overlap

## Scale options

The PowerShell reader and upload UI support these plan scales:

- `1/8 in = 1 ft`
- `3/16 in = 1 ft`
- `1/4 in = 1 ft`
- `1/2 in = 1 ft`

## PDF and OCR support

- Text PDFs: the program searches for embedded plan JSON or labeled room data
- Scanned/image PDFs: the program falls back to OCR when local tools are available
- OCR tools required for scanned PDFs:
  - `tesseract`
  - `pdftoppm` or `magick`

If OCR tools are not installed, scanned/image PDFs will fail with a helpful error.

## Run

PowerShell CLI:

```powershell
.\plan_reader.ps1 .\sample_plan.json -Scale "1/4 in = 1 ft"
.\plan_reader.ps1 .\plan.pdf -Scale "1/8 in = 1 ft"
```

PowerShell upload UI:

```powershell
.\plan_reader_ui.ps1
```

## VS Code

- Press `F5` and choose `Open Plan Reader Upload UI`
- Run `Terminal: Run Build Task` to open the upload UI as the default task
- Use the scale dropdown in the `Upload Floor Plan Pdf` section before processing the plan
- Install the recommended PowerShell extension if VS Code prompts for it
