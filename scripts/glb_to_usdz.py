#!/usr/bin/env python3
"""Offline importer for Protacta's reviewed static glTF 2.0 mesh profile.

Uses usd-core==26.11 in an authoring venv, never an iOS dependency. Preserves
mesh topology, node transforms, base-color textures and tangent-space normals.
Unsupported geometry/material features fail explicitly instead of disappearing.
OpenUSD reference: https://openusd.org/release/tut_simple_shading.html
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct


class GLB:
    def __init__(self, path):
        self.path = Path(path).resolve()
        self.data = self.path.read_bytes()
        magic, version, length = struct.unpack_from('<4sII', self.data)
        if (magic, version, length) != (b'glTF', 2, len(self.data)):
            raise ValueError('Expected a complete glTF 2.0 binary file')
        offset, chunks = 12, {}
        while offset < length:
            count, kind = struct.unpack_from('<II', self.data, offset)
            offset += 8
            if offset + count > length or kind in chunks:
                raise ValueError('Invalid or duplicate GLB chunk')
            chunks[kind] = self.data[offset:offset + count]
            offset += count
        self.doc = json.loads(chunks[0x4E4F534A])
        self.binary = chunks.get(0x004E4942, b'')
        if self.doc.get('extensionsRequired') or self.doc.get('skins') or self.doc.get('animations'):
            raise ValueError('This reviewed profile supports static meshes without required extensions')
        buffers = self.doc.get('buffers', [])
        if len(buffers) != 1 or 'uri' in buffers[0] or buffers[0]['byteLength'] > len(self.binary):
            raise ValueError('Expected one embedded binary buffer')

    def buffer_view(self, index):
        view = self.doc['bufferViews'][index]
        start = view.get('byteOffset', 0)
        end = start + view['byteLength']
        if view.get('buffer', 0) != 0 or start < 0 or end > len(self.binary):
            raise ValueError('Buffer view is outside the binary data')
        return view, self.binary[start:end]

    def accessor(self, index):
        accessor = self.doc['accessors'][index]
        if 'sparse' in accessor or 'bufferView' not in accessor:
            raise ValueError('Sparse or implicit accessors need a separate import review')
        formats = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
        widths = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
        width = widths[accessor['type']]
        component = accessor['componentType']
        unpack = struct.Struct('<' + formats[component] * width)
        view, data = self.buffer_view(accessor['bufferView'])
        stride = view.get('byteStride', unpack.size)
        start, count = accessor.get('byteOffset', 0), accessor['count']
        if count <= 0 or stride < unpack.size or start < 0 or start + (count - 1) * stride + unpack.size > len(data):
            raise ValueError('Accessor exceeds its buffer view')
        values = [unpack.unpack_from(data, start + i * stride) for i in range(count)]
        if accessor.get('normalized'):
            limits = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535}
            divisor = limits[component]
            values = [tuple(max(-1, v / divisor) for v in row) for row in values]
        if not all(math.isfinite(v) for row in values for v in row):
            raise ValueError('Nonfinite mesh data')
        return values


def group_nodes(doc, grouping):
    """Reparent declared siblings into semantic motion groups; never join meshes."""
    if not grouping:
        return
    nodes = doc['nodes']
    roots = doc['scenes'][doc.get('scene', 0)]['nodes']
    if len(roots) != 1:
        raise ValueError('Grouping currently requires one source root')
    root = nodes[roots[0]]
    children = set(root.get('children', []))
    by_name = {}
    for index in children:
        name = nodes[index].get('name')
        if name in by_name:
            raise ValueError('Ambiguous source name in grouping')
        by_name[name] = index
    claimed, groups = set(), []
    for name, members in grouping.items():
        indices = [by_name[member] for member in members]
        if not indices or claimed.intersection(indices):
            raise ValueError('Each grouped node must have exactly one owner')
        claimed.update(indices)
        groups.append(len(nodes))
        nodes.append({'name': name, 'children': indices})
    if claimed != children:
        raise ValueError('Grouping must account for every source child')
    root['children'] = groups


def convert(source, output, grouping=None):
    from pxr import Gf, Kind, Sdf, Usd, UsdGeom, UsdShade, UsdValidation
    source = GLB(source)
    output = Path(output).resolve()
    if output == source.path.parent or output in source.path.parents:
        raise ValueError('Derived output must be separate from original storage')
    output.mkdir(parents=True, exist_ok=False)
    doc = source.doc
    group_nodes(doc, grouping)
    stage_file = output / 'model.usdc'
    stage = Usd.Stage.CreateNew(str(stage_file))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    model = UsdGeom.Xform.Define(stage, '/Model')
    stage.SetDefaultPrim(model.GetPrim())
    Usd.ModelAPI(model).SetKind(Kind.Tokens.component)
    digest = hashlib.sha256(source.data).hexdigest()
    stage.GetRootLayer().customLayerData = {'sourceSHA256': digest, 'sourceCopyright': doc.get('asset', {}).get('copyright', '')}

    images = []
    for index, image in enumerate(doc.get('images', [])):
        if image.get('mimeType') not in ('image/png', 'image/jpeg') or 'bufferView' not in image:
            raise ValueError('Expected embedded PNG/JPEG images')
        suffix = '.png' if image['mimeType'] == 'image/png' else '.jpg'
        relative = Path('textures') / f'image_{index:03d}{suffix}'
        (output / relative).parent.mkdir(exist_ok=True)
        (output / relative).write_bytes(source.buffer_view(image['bufferView'])[1])
        images.append(relative.as_posix())

    materials = []
    def texture(material, name, spec, color_space, scale, bias=(0, 0, 0, 0)):
        if spec.get('texCoord', 0) != 0 or spec.get('extensions'):
            raise ValueError('Texture transforms or secondary UVs need an import review')
        tex = doc['textures'][spec['index']]
        sampler = doc.get('samplers', [{}])[tex.get('sampler', 0)]
        reader = UsdShade.Shader.Define(stage, material.GetPath().AppendChild(name + '_st'))
        reader.CreateIdAttr('UsdPrimvarReader_float2')
        reader.CreateInput('varname', Sdf.ValueTypeNames.String).Set('st')
        shader = UsdShade.Shader.Define(stage, material.GetPath().AppendChild(name))
        shader.CreateIdAttr('UsdUVTexture')
        shader.CreateInput('file', Sdf.ValueTypeNames.Asset).Set(Sdf.AssetPath(images[tex['source']]))
        shader.CreateInput('st', Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), 'result')
        shader.CreateInput('sourceColorSpace', Sdf.ValueTypeNames.Token).Set(color_space)
        shader.CreateInput('scale', Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(*scale))
        shader.CreateInput('bias', Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(*bias))
        wraps = {10497: 'repeat', 33071: 'clamp', 33648: 'mirror'}
        for axis in ('S', 'T'):
            shader.CreateInput('wrap' + axis, Sdf.ValueTypeNames.Token).Set(wraps[sampler.get('wrap' + axis, 10497)])
        shader.CreateOutput('rgb', Sdf.ValueTypeNames.Float3)
        shader.CreateOutput('a', Sdf.ValueTypeNames.Float)
        return shader

    for index, spec in enumerate(doc.get('materials', [])):
        pbr = spec.get('pbrMetallicRoughness', {})
        if spec.get('extensions') or pbr.get('metallicRoughnessTexture') or spec.get('occlusionTexture') or spec.get('emissiveTexture'):
            raise ValueError('Unsupported material channels; refusing silent material loss')
        material = UsdShade.Material.Define(stage, f'/Model/Materials/material_{index:03d}')
        material.GetPrim().SetDisplayName(spec.get('name', f'Material {index}'))
        shader = UsdShade.Shader.Define(stage, material.GetPath().AppendChild('Surface'))
        shader.CreateIdAttr('UsdPreviewSurface')
        color = pbr.get('baseColorFactor', [1, 1, 1, 1])
        shader.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*color[:3]))
        shader.CreateInput('metallic', Sdf.ValueTypeNames.Float).Set(pbr.get('metallicFactor', 1))
        shader.CreateInput('roughness', Sdf.ValueTypeNames.Float).Set(pbr.get('roughnessFactor', 1))
        shader.CreateInput('emissiveColor', Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*spec.get('emissiveFactor', [0, 0, 0])))
        alpha = spec.get('alphaMode', 'OPAQUE')
        if alpha not in ('OPAQUE', 'BLEND'):
            raise ValueError('Alpha masking needs a separate material review')
        shader.CreateInput('opacity', Sdf.ValueTypeNames.Float).Set(color[3] if alpha == 'BLEND' else 1)
        if 'baseColorTexture' in pbr:
            tex = texture(material, 'BaseColor', pbr['baseColorTexture'], 'sRGB', color)
            shader.GetInput('diffuseColor').ConnectToSource(tex.ConnectableAPI(), 'rgb')
            if alpha == 'BLEND':
                shader.GetInput('opacity').ConnectToSource(tex.ConnectableAPI(), 'a')
        if 'normalTexture' in spec:
            amount = spec['normalTexture'].get('scale', 1)
            tex = texture(material, 'Normal', spec['normalTexture'], 'raw', (2 * amount, 2 * amount, 2, 1), (-amount, -amount, -1, 0))
            shader.CreateInput('normal', Sdf.ValueTypeNames.Normal3f).ConnectToSource(tex.ConnectableAPI(), 'rgb')
        material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), 'surface')
        materials.append(material)

    report = {'source': str(source.path), 'sourceSHA256': digest, 'usdVersion': list(Usd.GetVersion()),
              'sourceCopyright': doc.get('asset', {}).get('copyright'), 'groups': grouping,
              'nodes': [], 'meshes': [], 'materialCount': len(materials), 'textureFiles': images,
              'units': 'metres', 'upAxis': 'Y', 'triangles': 0}
    visited = set()
    def node(index, parent):
        if index in visited:
            raise ValueError('Cyclic or multiply-parented node graph')
        visited.add(index)
        spec = doc['nodes'][index]
        name = re.sub(r'[^A-Za-z0-9_]', '_', spec.get('name', 'Node'))
        path = parent.AppendChild(f'n{index:03d}_{name}')
        xform = UsdGeom.Xform.Define(stage, path)
        if 'matrix' in spec:
            values = spec['matrix']
            matrix = Gf.Matrix4d(*values)
        else:
            transform = Gf.Transform()
            transform.SetTranslation(Gf.Vec3d(*spec.get('translation', [0, 0, 0])))
            rotation = spec.get('rotation', [0, 0, 0, 1])
            transform.SetRotation(Gf.Rotation(Gf.Quatd(rotation[3], Gf.Vec3d(*rotation[:3]))))
            transform.SetScale(Gf.Vec3d(*spec.get('scale', [1, 1, 1])))
            matrix = transform.GetMatrix()
        xform.AddTransformOp().Set(matrix)
        xform.GetPrim().SetCustomDataByKey('sourceNodeName', spec.get('name', ''))
        report['nodes'].append({'sourceIndex': index, 'sourceName': spec.get('name'), 'entityName': path.name, 'usdPath': str(path)})
        if 'mesh' in spec:
            for primitive_index, primitive in enumerate(doc['meshes'][spec['mesh']]['primitives']):
                if primitive.get('mode', 4) != 4 or primitive.get('targets') or primitive.get('extensions'):
                    raise ValueError('Only uncompressed static triangles are supported')
                attributes = primitive['attributes']
                points = source.accessor(attributes['POSITION'])
                indices = [r[0] for r in source.accessor(primitive['indices'])] if 'indices' in primitive else list(range(len(points)))
                if len(indices) % 3 or min(indices) < 0 or max(indices) >= len(points):
                    raise ValueError('Invalid triangle indices')
                mesh = UsdGeom.Mesh.Define(stage, path.AppendChild(f'mesh_{primitive_index:03d}'))
                mesh.CreatePointsAttr(points)
                mesh.CreateFaceVertexCountsAttr([3] * (len(indices) // 3))
                mesh.CreateFaceVertexIndicesAttr(indices)
                mesh.CreateSubdivisionSchemeAttr('none')
                mesh.CreateExtentAttr([[min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]])
                if 'NORMAL' in attributes:
                    normals = source.accessor(attributes['NORMAL'])
                    if len(normals) != len(points):
                        raise ValueError('Normal and position counts differ')
                    mesh.CreateNormalsAttr(normals); mesh.SetNormalsInterpolation('vertex')
                if 'TEXCOORD_0' in attributes:
                    uv = source.accessor(attributes['TEXCOORD_0'])
                    if len(uv) != len(points):
                        raise ValueError('UV and position counts differ')
                    UsdGeom.PrimvarsAPI(mesh).CreatePrimvar('st', Sdf.ValueTypeNames.TexCoord2fArray, 'vertex').Set([(u, 1 - v) for u, v in uv])
                if 'material' in primitive:
                    mid = primitive['material']
                    UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(materials[mid])
                    mesh.CreateDoubleSidedAttr(doc['materials'][mid].get('doubleSided', False))
                triangles = len(indices) // 3
                report['triangles'] += triangles
                report['meshes'].append({'path': str(mesh.GetPath()), 'vertices': len(points), 'triangles': triangles})
        for child in spec.get('children', []):
            node(child, path)

    for root in doc['scenes'][doc.get('scene', 0)]['nodes']:
        node(root, model.GetPath())
    stage.GetRootLayer().Save()
    package = output / 'model.usdz'
    # This generated stage references only the extracted images listed above.
    # Sdf's USDZ writer preserves those paths and the required ZIP alignment.
    with Sdf.ZipFileWriter.CreateNew(str(package)) as writer:
        if not writer.AddFile(str(stage_file), 'model.usdc'):
            raise ValueError('Cannot add the USD root layer')
        for image in images:
            if not writer.AddFile(str(output / image), image):
                raise ValueError('Cannot package a declared texture')
    reopened = Usd.Stage.Open(str(package))
    bounds = UsdGeom.BBoxCache(Usd.TimeCode.Default(), ['default', 'render']).ComputeWorldBound(reopened.GetDefaultPrim()).ComputeAlignedRange()
    report['bounds'] = {'min': list(bounds.GetMin()), 'max': list(bounds.GetMax())}
    registry = UsdValidation.ValidationRegistry()
    validators = registry.GetOrLoadAllValidators()
    issues = UsdValidation.ValidationContext(validators).Validate(reopened)
    report['validation'] = [{'type': str(e.GetType()), 'message': e.GetMessage()} for e in issues]
    report['normalStrengthPolicy'] = 'Preserve glTF XY normal strength in UsdUVTexture scale/bias; non-default strength may produce a validator advisory'
    report['resolvedTextureCount'] = 0
    for prim in reopened.Traverse():
        if prim.IsA(UsdShade.Shader):
            value = UsdShade.Shader(prim).GetInput('file')
            if value:
                if not value.Get().resolvedPath:
                    raise ValueError('A packaged texture does not resolve')
                report['resolvedTextureCount'] += 1
    report['packageSHA256'] = hashlib.sha256(package.read_bytes()).hexdigest()
    report['packageBytes'] = package.stat().st_size
    (output / 'review.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['sourceSHA256', 'triangles', 'materialCount', 'bounds', 'packageBytes', 'validation']}, indent=2))
    if any(e.GetType() == UsdValidation.ValidationErrorType.Error for e in issues):
        raise ValueError('OpenUSD validation reported errors; inspect review.json')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path, help='New derived directory; never an original-file directory')
    parser.add_argument('--groups', type=Path, help='Reviewed semantic grouping JSON keyed by group name')
    args = parser.parse_args()
    convert(args.source, args.output, json.loads(args.groups.read_text()) if args.groups else None)
