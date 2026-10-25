import Foundation
import simd

/// Display-only surface grouping for the elephant study. Original positions,
/// UVs, faces, normals, actions and physical area are retained unchanged.
/// A frame does not carry full folding history: depth is a deterministic
/// source-based display ordering of coincident continuous paper surfaces.
enum ElephantRenderSurface {
    private struct Edge {let face:Int;let index:Int;let a:PaperVertex;let b:PaperVertex}
    private struct Interval {let low:Float;let high:Float}
    private static let sourceTolerance:Float=0.0000005
    private static let positionTolerance:Float=0.000002

    static func apply(to input:PaperFrame)->PaperFrame {
        let count=input.faces.count
        guard count>0 else{return input}
        let faces=input.faces,normals=faces.map(\.normal)
        let centers=faces.map {f in f.vertices.reduce(SIMD2<Float>.zero){$0+$1.source}/Float(f.vertices.count)}
        let edges=faces.enumerated().flatMap {i,f in f.vertices.indices.map {Edge(face:i,index:$0,a:f.vertices[$0],b:f.vertices[($0+1)%f.vertices.count])}}
        var parent=Array(0..<count)
        func root(_ i:Int)->Int {var a=i;while parent[a] != a {a=parent[a]};return a}
        func join(_ a:Int,_ b:Int){let x=root(a),y=root(b);if x != y {parent[max(x,y)]=min(x,y)}}
        func cross(_ a:SIMD2<Float>,_ b:SIMD2<Float>)->Float {a.x*b.y-a.y*b.x}
        var coverage=faces.map {f in f.vertices.map {_ in [Interval]()}}
        for i in edges.indices {
            let a=edges[i],delta=a.b.source-a.a.source,length=simd_length(delta)
            guard length>sourceTolerance else{continue}
            let direction=delta/length,ownSide=cross(direction,centers[a.face]-a.a.source)
            for j in (i+1)..<edges.count {
                let b=edges[j]
                guard a.face != b.face,simd_dot(normals[a.face],normals[b.face])>0.9999,
                      ownSide*cross(direction,centers[b.face]-a.a.source)<0,
                      abs(cross(direction,b.a.source-a.a.source))<sourceTolerance,
                      abs(cross(direction,b.b.source-a.a.source))<sourceTolerance else{continue}
                let start=simd_dot(b.a.source-a.a.source,direction),end=simd_dot(b.b.source-a.a.source,direction)
                let low=max(0,min(start,end)),high=min(length,max(start,end))
                guard high-low>sourceTolerance,abs(end-start)>sourceTolerance else{continue}
                var connected=true
                for distance in [low,high] {
                    let p=a.a.position+(a.b.position-a.a.position)*(distance/length)
                    let q=b.a.position+(b.b.position-b.a.position)*((distance-start)/(end-start))
                    if simd_distance(p,q)>positionTolerance {connected=false;break}
                }
                guard connected else{continue}
                // Adjacent source pieces must share the same physical plane,
                // not only an edge and an approximately parallel normal.
                guard b.a.position.distance(toPlaneThrough:a.a.position,normal:normals[a.face])<positionTolerance,
                      b.b.position.distance(toPlaneThrough:a.a.position,normal:normals[a.face])<positionTolerance else{continue}
                join(a.face,b.face)
                coverage[a.face][a.index].append(Interval(low:low,high:high))
                let bLength=simd_distance(b.a.source,b.b.source)
                let p=(low-start)/(end-start)*bLength,q=(high-start)/(end-start)*bLength
                coverage[b.face][b.index].append(Interval(low:min(p,q),high:max(p,q)))
            }
        }
        var members=[Int:[Int]]()
        for i in 0..<count {members[root(i),default:[]].append(i)}
        let groups=members.values.sorted {($0.min() ?? 0)<($1.min() ?? 0)}
        struct Surface {let indices:[Int];let normal:SIMD3<Float>;let origin:SIMD3<Float>;let uv:SIMD2<Float>;let minUV:SIMD2<Float>}
        let surfaces=groups.map {indices -> Surface in
            var total:Float=0,uv=SIMD2<Float>.zero,n=SIMD3<Float>.zero,minUV=SIMD2<Float>(repeating:.greatestFiniteMagnitude)
            for i in indices {
                let f=faces[i]
                for j in 1..<(f.vertices.count-1) {
                    let a=f.vertices[0].source,b=f.vertices[j].source,c=f.vertices[j+1].source
                    let area=abs(cross(b-a,c-a))/2
                    uv+=(a+b+c)/3*area;total+=area
                }
                n+=normals[i]*f.area
                for v in f.vertices {minUV=simd_min(minUV,v.source)}
            }
            n=simd_normalize(n)
            var dominant=0
            if abs(n.y)>abs(n[dominant]) {dominant=1};if abs(n.z)>abs(n[dominant]) {dominant=2}
            if n[dominant]<0 {n = -n}
            return Surface(indices:indices,normal:n,origin:faces[indices[0]].vertices[0].position,uv:uv/max(total,1e-12),minUV:minUV)
        }
        var planes=[[Int]]()
        for i in surfaces.indices {
            let a=surfaces[i]
            if let p=planes.firstIndex(where:{ids in
                let b=surfaces[ids[0]]
                return simd_dot(a.normal,b.normal)>0.9999 && abs(simd_dot(a.origin-b.origin,b.normal))<positionTolerance
            }) {planes[p].append(i)} else{planes.append([i])}
        }
        var offsets=Array(repeating:SIMD3<Float>.zero,count:count)
        for plane in planes {
            let sorted=plane.sorted {a,b in
                let x=surfaces[a],y=surfaces[b]
                if abs(x.uv.y-y.uv.y)>sourceTolerance {return x.uv.y<y.uv.y}
                if abs(x.uv.x-y.uv.x)>sourceTolerance {return x.uv.x<y.uv.x}
                if abs(x.minUV.y-y.minUV.y)>sourceTolerance {return x.minUV.y<y.minUV.y}
                return x.minUV.x<y.minUV.x
            }
            let gap=min(Float(0.00018),Float(0.0013)/Float(max(1,sorted.count-1)))
            for (rank,index) in sorted.enumerated() {
                let surface=surfaces[index],offset=surface.normal*(Float(rank)-Float(sorted.count-1)/2)*gap
                for i in surface.indices {offsets[i]=offset}
            }
        }
        var result=input
        for i in 0..<count {
            for j in result.faces[i].vertices.indices {result.faces[i].vertices[j].separation=offsets[i]}
            result.faces[i].outlinedEdges=faces[i].vertices.indices.map {j in
                if let mask=faces[i].outlinedEdges,j<mask.count,!mask[j] {return false}
                let length=simd_distance(faces[i].vertices[j].source,faces[i].vertices[(j+1)%faces[i].vertices.count].source)
                guard length>sourceTolerance else{return false}
                var end:Float=0
                for interval in coverage[i][j].sorted(by:{$0.low<$1.low}) {
                    if interval.low>end+sourceTolerance {return true}
                    end=max(end,interval.high)
                }
                return end<length-sourceTolerance
            }
        }
        return result
    }
}

private extension SIMD3 where Scalar == Float {
    func distance(toPlaneThrough origin:SIMD3<Float>,normal:SIMD3<Float>)->Float {abs(simd_dot(self-origin,normal))}
}
