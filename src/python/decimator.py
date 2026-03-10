#!/usr/bin/env python3
"""Simple mesh decimator + watertight cleanup pass for SketchUp plugin."""

from __future__ import annotations

import json
import math
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Sequence, Tuple


@dataclass
class Mesh:
  points: List[List[float]]
  faces: List[List[int]]


def load_payload(path: Path) -> Tuple[float, Mesh]:
  payload = json.loads(path.read_text())
  level = float(payload.get("level", 0.0))
  mesh_raw = payload.get("mesh", {})
  points = mesh_raw.get("points", [])
  faces = mesh_raw.get("faces", [])
  return level, Mesh(points=points, faces=faces)


def edge_lengths(mesh: Mesh) -> List[float]:
  lengths: List[float] = []
  for face in mesh.faces:
    if len(face) < 3:
      continue
    for index, a in enumerate(face):
      b = face[(index + 1) % len(face)]
      pa = mesh.points[a]
      pb = mesh.points[b]
      lengths.append(math.dist(pa, pb))
  return lengths


def vertex_cluster_decimation(mesh: Mesh, level: float) -> Mesh:
  if not mesh.points or not mesh.faces:
    return mesh

  lengths = edge_lengths(mesh)
  avg_edge = (sum(lengths) / len(lengths)) if lengths else 1.0
  cluster_size = max(avg_edge * (0.5 + level * 3.5), 1e-6)

  cluster_to_index: Dict[Tuple[int, int, int], int] = {}
  new_points: List[List[float]] = []
  remap: Dict[int, int] = {}

  for idx, point in enumerate(mesh.points):
    key = (
      int(round(point[0] / cluster_size)),
      int(round(point[1] / cluster_size)),
      int(round(point[2] / cluster_size)),
    )
    if key not in cluster_to_index:
      cluster_to_index[key] = len(new_points)
      new_points.append(point)
    remap[idx] = cluster_to_index[key]

  new_faces: List[List[int]] = []
  seen = set()
  for face in mesh.faces:
    mapped = [remap[i] for i in face]
    deduped = []
    for i in mapped:
      if not deduped or deduped[-1] != i:
        deduped.append(i)
    deduped = [i for n, i in enumerate(deduped) if i not in deduped[:n]]
    if len(deduped) < 3:
      continue
    key = tuple(sorted(deduped))
    if key in seen:
      continue
    seen.add(key)
    new_faces.append(deduped)

  return Mesh(points=new_points, faces=new_faces)


def watertight_cleanup(mesh: Mesh) -> Mesh:
  edge_count = defaultdict(int)
  for face in mesh.faces:
    for i, a in enumerate(face):
      b = face[(i + 1) % len(face)]
      edge = tuple(sorted((a, b)))
      edge_count[edge] += 1

  cleaned_faces: List[List[int]] = []
  for face in mesh.faces:
    boundary_edges = 0
    for i, a in enumerate(face):
      b = face[(i + 1) % len(face)]
      if edge_count[tuple(sorted((a, b)))] == 1:
        boundary_edges += 1
    if boundary_edges <= 1:
      cleaned_faces.append(face)

  return Mesh(points=mesh.points, faces=cleaned_faces)


def write_result(path: Path, original: Mesh, simplified: Mesh, final: Mesh) -> None:
  payload = {
    "points": final.points,
    "faces": final.faces,
    "original_faces": len(original.faces),
    "reduced_faces": len(simplified.faces),
    "final_faces": len(final.faces),
  }
  path.write_text(json.dumps(payload))


def main(argv: Sequence[str]) -> int:
  if len(argv) != 3:
    print("Usage: decimator.py <input.json> <output.json>", file=sys.stderr)
    return 1

  input_path = Path(argv[1])
  output_path = Path(argv[2])

  level, original = load_payload(input_path)
  simplified = vertex_cluster_decimation(original, max(0.0, min(level, 1.0)))
  final = watertight_cleanup(simplified)
  write_result(output_path, original, simplified, final)
  return 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv))
