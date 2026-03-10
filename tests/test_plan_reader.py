import json
import tempfile
import unittest
from pathlib import Path

from plan_reader import PlanError, load_plan, render_map, render_room_dimensions


class PlanReaderTests(unittest.TestCase):
    def _write_plan(self, payload: dict) -> Path:
        tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False)
        with tmp:
            json.dump(payload, tmp)
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


if __name__ == "__main__":
    unittest.main()
