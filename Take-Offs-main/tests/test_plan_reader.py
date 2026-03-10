import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from plan_reader import PlanError, load_plan, render_map, render_room_dimensions


class PlanReaderTests(unittest.TestCase):
    def _write_plan(self, payload: dict) -> Path:
        tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False)
        with tmp:
            json.dump(payload, tmp)
        return Path(tmp.name)

    def _write_pdf(self, text_payload: str) -> Path:
        pdf_bytes = (
            b"%PDF-1.4\n"
            b"1 0 obj\n<< /Length "
            + str(len(text_payload.encode("utf-8"))).encode("ascii")
            + b" >>\nstream\n"
            + text_payload.encode("utf-8")
            + b"\nendstream\nendobj\n%%EOF\n"
        )
        tmp = tempfile.NamedTemporaryFile(mode="wb", suffix=".pdf", delete=False)
        with tmp:
            tmp.write(pdf_bytes)
        return Path(tmp.name)

    def test_load_valid_plan(self):
        path = self._write_plan(
            {
                "unit": "m",
                "rooms": [
                    {"name": "A", "x": 0, "y": 0, "width": 2, "height": 2},
                    {"name": "B", "x": 2, "y": 0, "width": 1, "height": 2},
                ],
            }
        )
        plan = load_plan(path)
        self.assertEqual(len(plan.rooms), 2)
        self.assertEqual(plan.rooms[0].area, 4)

    def test_load_plan_from_pdf(self):
        path = self._write_pdf(
            '{"unit":"m","rooms":[{"name":"Living","x":0,"y":0,"width":6,"height":4}]}'
        )
        plan = load_plan(path)
        self.assertEqual(plan.unit, "m")
        self.assertEqual(len(plan.rooms), 1)
        self.assertEqual(plan.rooms[0].name, "Living")
        self.assertEqual(plan.rooms[0].area, 24)

    def test_load_scanned_pdf_with_ocr(self):
        path = self._write_pdf("Scanned image data only")
        with patch(
            "plan_reader._ocr_pdf_text",
            return_value="Unit: m\nName: Living X: 0 Y: 0 Width: 6 Height: 4",
        ):
            plan = load_plan(path)

        self.assertEqual(plan.unit, "m")
        self.assertEqual(len(plan.rooms), 1)
        self.assertEqual(plan.rooms[0].name, "Living")
        self.assertEqual(plan.rooms[0].perimeter, 20)

    def test_pdf_without_plan_json_raises(self):
        path = self._write_pdf("This PDF has no usable plan data.")
        with patch("plan_reader._ocr_pdf_text", return_value=None):
            with self.assertRaises(PlanError):
                load_plan(path)

    def test_overlap_raises(self):
        path = self._write_plan(
            {
                "unit": "m",
                "rooms": [
                    {"name": "A", "x": 0, "y": 0, "width": 3, "height": 2},
                    {"name": "B", "x": 2, "y": 0, "width": 3, "height": 2},
                ],
            }
        )
        with self.assertRaises(PlanError):
            load_plan(path)

    def test_render_outputs(self):
        path = self._write_plan(
            {
                "unit": "m",
                "rooms": [
                    {"name": "Kitchen", "x": 0, "y": 0, "width": 2, "height": 1}
                ],
            }
        )
        plan = load_plan(path)
        map_output = render_map(plan)
        dimensions_output = render_room_dimensions(plan)
        self.assertIn("Legend", map_output)
        self.assertIn("Kitchen", dimensions_output)
        self.assertIn("Total area", dimensions_output)
        self.assertIn("m^2", dimensions_output)


if __name__ == "__main__":
    unittest.main()
