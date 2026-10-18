//! Copy sim rows into Godot values.
//!
//! Every collection here is a fresh Godot value. Nothing in it borrows sim
//! memory: the caller owns the copy once the function returns.

use godot::prelude::*;
use latchsoil_sim::{BuildingView, Catalog, NodeView, PersonView, Rejections, Snapshot};

/// 16 lowercase hex digits. A Godot int is i64, so the u64 hash must not cross
/// as a number.
pub(crate) fn hash_hex(hash: u64) -> String {
    format!("{hash:016x}")
}

pub(crate) fn snapshot(snap: &Snapshot) -> VarDictionary {
    let mut dict = VarDictionary::new();
    dict.set("tick", widen_u64(snap.tick));
    dict.set("people", &people_array(&snap.people));
    dict.set("buildings", &buildings_array(&snap.buildings));
    dict.set("nodes", &nodes_array(&snap.nodes));
    dict.set("removed", &pairs(&snap.removed));
    dict.set("hash", hash_hex(snap.hash).as_str());
    dict.set("full", snap.full);
    dict.set("error", i64::from(snap.error));
    dict
}

pub(crate) fn catalog(catalog: &Catalog) -> VarDictionary {
    let mut dict = VarDictionary::new();
    dict.set("items", &catalog_array(&catalog.items));
    dict.set("recipes", &catalog_array(&catalog.recipes));
    dict
}

pub(crate) fn rejections(rejections: &Rejections) -> VarDictionary {
    let mut dict = VarDictionary::new();
    dict.set("malformed", widen_u64(rejections.malformed));
    dict.set("stale", widen_u64(rejections.stale));
    dict.set("queue_full", widen_u64(rejections.queue_full));
    dict
}

fn people_array(people: &[PersonView]) -> VarArray {
    let mut array = VarArray::new();
    for person in people {
        let mut row = VarDictionary::new();
        row.set("index", i64::from(person.index));
        row.set("generation", i64::from(person.generation));
        row.set("x", f64::from(person.x));
        row.set("y", f64::from(person.y));
        row.set("hunger", f64::from(person.hunger));
        row.set("thirst", f64::from(person.thirst));
        row.set("health", f64::from(person.health));
        row.set("job", i64::from(person.job));
        row.set("failure", i64::from(person.failure));
        row.set("failure_text", person.failure_text.as_str());
        row.set("drafted", person.drafted);
        row.set("carried", &carried_array(&person.carried));
        row.set("path", &packed_path(&person.path));
        row.set("dest", &floats_array(&person.dest));
        row.set("target", &uints_array(&person.target));
        array.push(&row.to_variant());
    }
    array
}

fn buildings_array(buildings: &[BuildingView]) -> VarArray {
    let mut array = VarArray::new();
    for building in buildings {
        let mut row = VarDictionary::new();
        row.set("index", i64::from(building.index));
        row.set("generation", i64::from(building.generation));
        row.set("kind", i64::from(building.kind));
        row.set("x", f64::from(building.x));
        row.set("y", f64::from(building.y));
        array.push(&row.to_variant());
    }
    array
}

fn nodes_array(nodes: &[NodeView]) -> VarArray {
    let mut array = VarArray::new();
    for node in nodes {
        let mut row = VarDictionary::new();
        row.set("index", i64::from(node.index));
        row.set("generation", i64::from(node.generation));
        row.set("x", f64::from(node.x));
        row.set("y", f64::from(node.y));
        row.set("remaining", i64::from(node.remaining));
        row.set("yield_item", i64::from(node.yield_item));
        array.push(&row.to_variant());
    }
    array
}

fn catalog_array(rows: &[latchsoil_sim::CatalogRow]) -> VarArray {
    let mut array = VarArray::new();
    for row in rows {
        let mut item = VarDictionary::new();
        item.set("id", i64::from(row.id));
        item.set("name", row.name.as_str());
        array.push(&item.to_variant());
    }
    array
}

fn carried_array(carried: &[[u32; 2]]) -> VarArray {
    let mut array = VarArray::new();
    for pair in carried {
        array.push(&pair_array(pair[0], pair[1]).to_variant());
    }
    array
}

fn pairs(ids: &[[u32; 2]]) -> VarArray {
    let mut array = VarArray::new();
    for pair in ids {
        array.push(&pair_array(pair[0], pair[1]).to_variant());
    }
    array
}

fn pair_array(first: u32, second: u32) -> VarArray {
    let mut pair = VarArray::new();
    pair.push(&i64::from(first).to_variant());
    pair.push(&i64::from(second).to_variant());
    pair
}

fn packed_path(path: &[f32]) -> PackedFloat32Array {
    path.iter().copied().collect()
}

fn floats_array(values: &[f32]) -> VarArray {
    let mut array = VarArray::new();
    for value in values {
        array.push(&f64::from(*value).to_variant());
    }
    array
}

fn uints_array(values: &[u32]) -> VarArray {
    let mut array = VarArray::new();
    for value in values {
        array.push(&i64::from(*value).to_variant());
    }
    array
}

/// Godot's int is i64. A counter or tick that does not fit saturates instead of
/// panicking: player input must not abort the process.
fn widen_u64(value: u64) -> i64 {
    i64::try_from(value).unwrap_or(i64::MAX)
}
