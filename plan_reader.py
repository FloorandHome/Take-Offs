#!/usr/bin/env python3
"""Read a building plan, map each room, and list dimensions per room."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class Room:
    name: str
    x: int
    y: int
    width: int
    height: int

    @property
    def area(self) -> int:
        return self.width * self.height

    @property
    def perimeter(self) -> int:
        return 2 * (self.width + self.height)


@dataclass(frozen=True)
class BuildingPlan:
    unit: str
    rooms: list[Room]


class PlanError(ValueError):
    """Raised when a building plan is malformed."""


def _ensure_int(value: object, field: str, room_name: str) -> int:
    if not isinstance(value, int):
        raise PlanError(f"Room '{room_name}' has non-integer '{field}': {value!r}")
    return value


def load_plan(path: Path) -> BuildingPlan:
    data = json.loads(path.read_text(encoding="utf-8"))

    if not isinstance(data, dict):
        raise PlanError("Plan must be a JSON object")

    unit = data.get("unit", "m")
    if not isinstance(unit, str) or not unit.strip():
        raise PlanError("Field 'unit' must be a non-empty string")

    rooms_raw = data.get("rooms")
    if not isinstance(rooms_raw, list) or not rooms_raw:
        raise PlanError("Field 'rooms' must be a non-empty list")

    rooms: list[Room] = []
    for entry in rooms_raw:
        if not isinstance(entry, dict):
            raise PlanError("Each room entry must be an object")

        name = entry.get("name")
        if not isinstance(name, str) or not name.strip():
            raise PlanError("Every room needs a non-empty string 'name'")

        x = _ensure_int(entry.get("x"), "x", name)
        y = _ensure_int(entry.get("y"), "y", name)
        width = _ensure_int(entry.get("width"), "width", name)
        height = _ensure_int(entry.get("height"), "height", name)

        if width <= 0 or height <= 0:
            raise PlanError(f"Room '{name}' must have positive width and height")

        rooms.append(Room(name=name.strip(), x=x, y=y, width=width, height=height))

    _validate_no_overlap(rooms)
    return BuildingPlan(unit=unit.strip(), rooms=rooms)


def _validate_no_overlap(rooms: Iterable[Room]) -> None:
    rooms_list = list(rooms)
    for i, room_a in enumerate(rooms_list):
        for room_b in rooms_list[i + 1 :]:
            overlap_x = room_a.x < room_b.x + room_b.width and room_b.x < room_a.x + room_a.width
            overlap_y = room_a.y < room_b.y + room_b.height and room_b.y < room_a.y + room_a.height
            if overlap_x and overlap_y:
                raise PlanError(f"Rooms '{room_a.name}' and '{room_b.name}' overlap")


def _build_symbol_map(rooms: list[Room]) -> dict[str, str]:
    used: set[str] = set()
    symbol_map: dict[str, str] = {}
    fallback = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    for idx, room in enumerate(rooms):
        preferred = room.name.strip()[:1].upper()
        if preferred and preferred.isalnum() and preferred not in used:
            symbol = preferred
        else:
            symbol = next(ch for ch in fallback if ch not in used)
        used.add(symbol)
        symbol_map[room.name] = symbol
    return symbol_map


def render_map(plan: BuildingPlan) -> str:
    max_x = max(room.x + room.width for room in plan.rooms)
    max_y = max(room.y + room.height for room in plan.rooms)

    canvas = [["." for _ in range(max_x)] for _ in range(max_y)]
    symbol_map = _build_symbol_map(plan.rooms)
    for room in plan.rooms:
        symbol = symbol_map[room.name]
        for y in range(room.y, room.y + room.height):
            for x in range(room.x, room.x + room.width):
                canvas[y][x] = symbol

    rows = ["Building plan map (top view):"]
    for y in reversed(range(max_y)):
        rows.append(f"{y:>2} | " + " ".join(canvas[y]))
    rows.append("   + " + "-" * (2 * max_x - 1))
    rows.append("     " + " ".join(f"{x}" for x in range(max_x)))
    rows.append("Legend: " + ", ".join(f"{symbol_map[room.name]}={room.name}" for room in plan.rooms))
    return "\n".join(rows)


def render_room_dimensions(plan: BuildingPlan) -> str:
    unit2 = f"{plan.unit}^2"
    lines = [
        "Room dimensions:",
        f"{'Room':<20} {'Position (x,y)':<15} {'Width':<7} {'Height':<7} {'Area':<8} {'Perimeter':<10}",
        "-" * 75,
    ]
    total_area = 0
    for room in plan.rooms:
        total_area += room.area
        lines.append(
            f"{room.name:<20} ({room.x},{room.y}){'':<6} {room.width:<7}{room.height:<7}{str(room.area) + ' ' + unit2:<8}{str(room.perimeter) + ' ' + plan.unit:<10}"
        )

    lines.append("-" * 75)
    lines.append(f"Total area: {total_area} {unit2}")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Read a building plan JSON file, map each room, and list dimensions.",
    )
    parser.add_argument("plan_file", type=Path, help="Path to a building plan JSON file")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    plan = load_plan(args.plan_file)
    print(render_map(plan))
    print()
    print(render_room_dimensions(plan))


if __name__ == "__main__":
    main()
