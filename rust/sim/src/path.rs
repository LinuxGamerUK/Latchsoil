//! Pathfinding on the acre grid. No obstacles in milestone 1a.
//!
//! A point is in the acre when both axes are in `[0, 32)`. The cell is the
//! floor of each axis. Neighbour order is fixed (east, south, west, north).
//! Nothing here walks a `HashMap`.

use crate::rules::{
    dist, ACRE_CELLS, NEIGHBOURS, WAYPOINT_REACH_METERS,
};

/// Cell containing `(x, y)`, or `None` when the point is outside the acre
/// or not finite.
pub fn cell_of(x: f32, y: f32) -> Option<(i32, i32)> {
    if !(0.0..ACRE_CELLS as f32).contains(&x) || !(0.0..ACRE_CELLS as f32).contains(&y) {
        return None;
    }
    Some((x.floor() as i32, y.floor() as i32))
}

/// Waypoints from `from` to `to`, not including `from`.
///
/// `None` is no path: `to` (or `from`) is outside the acre. `Some(empty)` means
/// `from` is already within [`WAYPOINT_REACH_METERS`] of `to`. The last waypoint
/// is `to` itself, so the walker arrives at the ordered point, not merely its cell.
pub fn path_to(from: [f32; 2], to: [f32; 2]) -> Option<Vec<[f32; 2]>> {
    let start = cell_of(from[0], from[1])?;
    let goal = cell_of(to[0], to[1])?;
    if dist(from, to) <= WAYPOINT_REACH_METERS {
        return Some(Vec::new());
    }
    let cells = bfs(start, goal);
    Some(waypoints(&cells, to))
}

/// Spend up to `budget` meters along `path`. A waypoint within
/// [`WAYPOINT_REACH_METERS`] is reached and dropped.
pub fn advance_along(pos: &mut [f32; 2], path: &mut Vec<[f32; 2]>, mut budget: f32) {
    while budget > 0.0 && !path.is_empty() {
        let wp = path[0];
        let dx = wp[0] - pos[0];
        let dy = wp[1] - pos[1];
        let d = (dx * dx + dy * dy).sqrt();
        if d <= WAYPOINT_REACH_METERS {
            path.remove(0);
            continue;
        }
        if d <= budget {
            *pos = wp;
            budget -= d;
            path.remove(0);
            continue;
        }
        let scale = budget / d;
        pos[0] += dx * scale;
        pos[1] += dy * scale;
        budget = 0.0;
        let left_x = wp[0] - pos[0];
        let left_y = wp[1] - pos[1];
        if (left_x * left_x + left_y * left_y).sqrt() <= WAYPOINT_REACH_METERS {
            path.remove(0);
        }
    }
}

fn waypoints(cells: &[(i32, i32)], dest: [f32; 2]) -> Vec<[f32; 2]> {
    let mut out = Vec::new();
    for cell in cells.iter().skip(1) {
        out.push([cell.0 as f32, cell.1 as f32]);
    }
    if out.last().copied() != Some(dest) {
        out.push(dest);
    }
    out
}

/// Shortest path including both ends. Every in-acre cell is reachable.
fn bfs(start: (i32, i32), goal: (i32, i32)) -> Vec<(i32, i32)> {
    if start == goal {
        return vec![start];
    }
    let mut parent = [u16::MAX; (ACRE_CELLS * ACRE_CELLS) as usize];
    let mut queue = Vec::new();
    let start_i = index_of(start);
    parent[start_i] = start_i as u16;
    queue.push(start);
    let mut head = 0;
    while head < queue.len() {
        let current = queue[head];
        head += 1;
        if current == goal {
            break;
        }
        for (dx, dy) in NEIGHBOURS {
            let next = (current.0 + dx, current.1 + dy);
            if next.0 < 0 || next.1 < 0 || next.0 >= ACRE_CELLS || next.1 >= ACRE_CELLS {
                continue;
            }
            let ni = index_of(next);
            if parent[ni] != u16::MAX {
                continue;
            }
            parent[ni] = index_of(current) as u16;
            queue.push(next);
        }
    }
    let mut cells = vec![goal];
    let mut cursor = goal;
    while cursor != start {
        let p = parent[index_of(cursor)];
        debug_assert!(p != u16::MAX, "in-acre BFS missed a cell");
        cursor = ((p as i32) % ACRE_CELLS, (p as i32) / ACRE_CELLS);
        cells.push(cursor);
    }
    cells.reverse();
    cells
}

fn index_of(cell: (i32, i32)) -> usize {
    (cell.0 + cell.1 * ACRE_CELLS) as usize
}
