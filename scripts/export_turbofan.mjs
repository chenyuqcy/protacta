// Run with --experimental-loader or copy beside reviewed engine.js/blade.js and
// pinned three@0.185.1. No browser, server, shader execution or network is used.
// Source geometry: https://github.com/jubbon/jet-engine-3d
// Copyright (c) 2026 Dmitry Kulikov, MIT; retain the accompanying LICENSE.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { GLTFExporter } from 'three/addons/exporters/GLTFExporter.js';
import { writeFile } from 'node:fs/promises';

const mobile = process.argv.includes('--mobile');
const { buildEngine, MATS } = await import(mobile ? './engine_mobile.js' : './engine.js');

globalThis.FileReader = class {
  async readAsArrayBuffer(blob) {
    this.result = await blob.arrayBuffer(); this.onloadend?.();
  }
};
const target = process.argv[2];
if (!target) throw new Error('Provide a new output .glb path');
const source = buildEngine();
source.setSpiralBlur(0);
source.root.updateMatrixWorld(true);
const names = new Map(Object.entries(MATS).map(([key, mat]) => [mat.uuid, key]));
const root = new THREE.Group();
root.name = 'Turbofan_Structure';
const counts = [];
let removedEffects = 0;
for (const module of source.modules) {
  const exported = new THREE.Group(); exported.name = module.name;
  const buckets = new Map();
  module.traverse(object => {
    if (!object.isMesh || !object.visible) return;
    const material = object.material;
    if (Array.isArray(material)) throw new Error('Review multi-material geometry before export');
    if (material.visible === false || material.isShaderMaterial) { removedEffects++; return; }
    if (material.map || material.normalMap) throw new Error('This engine export expects source color materials');
    const bucket = buckets.get(material.uuid) ?? { material, geometries: [] };
    buckets.set(material.uuid, bucket);
    for (let instance = 0; instance < (object.isInstancedMesh ? object.count : 1); instance++) {
      const matrix = object.matrixWorld.clone();
      if (object.isInstancedMesh) {
        const local = new THREE.Matrix4(); object.getMatrixAt(instance, local); matrix.multiply(local);
      }
      const geometry = object.geometry.clone();
      for (const name of Object.keys(geometry.attributes)) {
        if (name !== 'position' && name !== 'normal') geometry.deleteAttribute(name);
      }
      if (!geometry.index) geometry.setIndex(Array.from({length:geometry.attributes.position.count},(_,i)=>i));
      geometry.applyMatrix4(matrix);
      geometry.scale(0.5, 0.5, 0.5); // upstream model unit = 0.50 metres
      if (!geometry.attributes.normal) geometry.computeVertexNormals();
      bucket.geometries.push(geometry);
    }
  });
  let triangles = 0;
  for (const {material, geometries} of buckets.values()) {
    const merged = mergeGeometries(geometries, false);
    if (!merged) throw new Error(`Cannot merge ${module.name}`);
    const surface = material.clone();
    if (surface.opacity === 1) surface.transparent = false;
    const mesh = new THREE.Mesh(merged, surface);
    mesh.name = `${module.name}_${names.get(material.uuid) ?? 'surface'}`;
    exported.add(mesh);
    triangles += merged.index.count / 3;
    geometries.forEach(g => g.dispose());
  }
  root.add(exported);
  counts.push({name:module.name, meshes:exported.children.length, triangles,
    explodedOffsetMetres:module.userData.explode.toArray().map(x=>x*0.5)});
}
const exporter = new GLTFExporter();
const buffer = await exporter.parseAsync(root, {binary:true, onlyVisible:true});
await writeFile(target, Buffer.from(buffer), {flag:'wx'});
await writeFile(target + '.review.json', JSON.stringify({
  source:'https://github.com/jubbon/jet-engine-3d', sourceCommit:'4acb4da958d34a367b11c0293235329e394baa21',
  copyright:'Copyright (c) 2026 Dmitry Kulikov', license:'MIT', units:'metres',
  changes:['Static structure export; original operational simulator is not included',
    'Source 0.5-metre units baked into vertex positions','Meshes merged only within module/material groups',
    'Invisible picking proxies and animated flame shader omitted'],
  removedEffects, modules:counts, triangles:counts.reduce((n,x)=>n+x.triangles,0)
  ,bladeSampling: mobile ? {radialMaximum:3,chordMaximum:6} : 'upstream'
},null,2)+'\n', {flag:'wx'});
console.log(JSON.stringify({bytes:buffer.byteLength, modules:counts, removedEffects},null,2));
