import SwiftUI
import SceneKit

//
// 不转相机,转地球: pitch(绕 X = 纬度)套 yaw(绕 Y = -经度)套球,屏幕正中永远是 (centerLat, centerLng)。
// 球是自己拼的经纬网格,UV 按等距圆柱自己给——SCNSphere 的接缝在哪不归我们管,换贴图就对不上。

enum StopoverStyle: String, CaseIterable {
    case marble, night, paper
    var title: String { ["marble": "蓝石", "night": "夜航", "paper": "旧图"][rawValue]! }

    var pin: UIColor { [.marble: UIColor(hex: 0xd8262f), .night: UIColor(hex: 0xff5a3c), .paper: UIColor(hex: 0xb3261e)][self]! }
    var arc: UIColor { [.marble: UIColor(hex: 0xf19a8f), .night: UIColor(hex: 0xecd2a6), .paper: UIColor(hex: 0xc0533f)][self]! }
    var atmosphere: UIColor? { [.marble: UIColor(hex: 0x8cc4ff), .night: UIColor(hex: 0xffcf8a)][self] }
    var star: UIColor { [.marble: UIColor(hex: 0xf2c25e), .night: UIColor(hex: 0xf5c96a), .paper: UIColor(hex: 0xb07a10)][self]! }
    var star2: UIColor { [.marble: UIColor(hex: 0x6cb4ff), .night: UIColor(hex: 0x78bcff), .paper: UIColor(hex: 0x3F5F86)][self]! }
    var label: UIColor { self == .paper ? UIColor(hex: 0x1F2A38) : UIColor(hex: 0xf3efe6) }
    var isDark: Bool { self != .paper }
}

/// 地球上要画的东西,一次性递进来,变了就整层重摆(量小: 几十个点、几十条线)
struct StopoverMarks: Equatable {
    struct Pin: Equatable { let id: String; let name: String; let lat: Double; let lng: Double; let count: Int }
    struct Arc: Equatable { let from: SIMD2<Double>; let to: SIMD2<Double> }
    struct Star: Equatable { let lat: Double; let lng: Double; let hers: Bool; let his: Bool }
    var pins: [Pin] = []
    var arcs: [Arc] = []
    var stars: [Star] = []
}

struct StopoverGlobe: UIViewRepresentable {
    var style: StopoverStyle
    var marks: StopoverMarks
    var places: [GlobeController.Place] = []
    /// 选中的城: 飞过去 + 描一圈
    var focus: SIMD2<Double>?
    /// 骰子: 每加一次,地球先甩开转半圈
    var kick = 0
    var onTap: (_ lat: Double, _ lng: Double, _ distance: Double) -> Void

    func makeCoordinator() -> GlobeController { GlobeController() }

    func makeUIView(context: Context) -> SCNView {
        let c = context.coordinator
        c.onTap = onTap
        c.setStyle(style)
        c.setMarks(marks)
        return c.view
    }

    func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        c.onTap = onTap
        c.setStyle(style)
        c.setMarks(marks)
        c.setPlaces(places)
        c.setKick(kick)
        c.setFocus(focus)
    }

    static func dismantleUIView(_ v: SCNView, coordinator: GlobeController) { coordinator.stop() }
}

@MainActor
final class GlobeController: NSObject, UIGestureRecognizerDelegate {
    let view = SCNView()
    private let scene = SCNScene()
    private let camera = SCNNode()
    private let pitch = SCNNode()
    private let yaw = SCNNode()
    private let earth = SCNNode()
    private let marksNode = SCNNode()
    private let labelsNode = SCNNode()
    private let halo = SCNNode()
    private let focusRing = SCNNode()

    var onTap: ((Double, Double, Double) -> Void)?

    // 视角(度)
    private var centerLat = 30.0, centerLng = 60.0
    private var distance = 3.5          // 相机到球心,球半径 1
    private var velocity = SIMD2<Double>(0, 0)
    private var lastTouch = Date.distantPast
    private var flight: (from: SIMD3<Double>, to: SIMD3<Double>, start: CFTimeInterval, dur: Double)?
    private var link: CADisplayLink?

    private var style: StopoverStyle?
    private var marks: StopoverMarks?
    private var focus: SIMD2<Double>?
    private var labelNodes: [SCNNode] = []
    /// (材质, 拉到最远时的半径): 线的粗细跟着视距走,屏幕上看着一样粗
    private var arcMats: [(SCNMaterial, Float)] = []
    /// 红线上的流星: 贴图沿线平移,亮头拖尾从出发地滑到目的地
    private struct Comet { let pts: [SIMD3<Float>]; let sprites: [SCNNode]; let offset: Double }
    private var comets: [Comet] = []
    /// Wish-star twinkle: (white overlay node, phase, period in seconds), driven per frame
    private var twinkles: [(node: SCNNode, phase: Double, period: Double)] = []
    private let cometPeriod = 7.0          // 秒/一轮: 跑完一趟约 4 秒,再歇 3 秒
    static let cometDots = 14
    private var dotScale: Float = 1
    /// 选中城时相机往下挪,城浮到抽屉上面那半屏里;没选时回到正中
    private var camShift = 0.0

    static let minDist = 1.22, maxDist = 5.2

    override init() {
        super.init()
        view.scene = scene
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true   // 流星一直在跑
        view.backgroundColor = .black

        let cam = SCNCamera()
        cam.fieldOfView = 40
        cam.projectionDirection = .horizontal   // 竖屏按宽算,球才不撑出屏幕
        cam.zNear = 0.01
        cam.zFar = 20
        camera.camera = cam
        scene.rootNode.addChildNode(camera)

        // 柔光跟着相机走: 左上打过来,背面不至于全黑
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 520
        key.eulerAngles = SCNVector3(-0.45, -0.55, 0)
        camera.addChildNode(key)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 620
        scene.rootNode.addChildNode(amb)

        earth.geometry = Self.sphere()
        yaw.addChildNode(earth)
        yaw.addChildNode(marksNode)
        yaw.addChildNode(labelsNode)
        yaw.addChildNode(focusRing)
        pitch.addChildNode(yaw)
        scene.rootNode.addChildNode(pitch)

        // 大气: 一张永远朝相机的平面,贴在球心,球自己把里圈挡掉
        halo.geometry = SCNPlane(width: 2, height: 2)
        halo.renderingOrder = -1
        scene.rootNode.addChildNode(halo)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        let dbl = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        tap.require(toFail: dbl)
        for g in [pan, pinch, tap, dbl] as [UIGestureRecognizer] { g.delegate = self; view.addGestureRecognizer(g) }

        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
        apply()
    }

    func stop() { link?.invalidate(); link = nil }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

    // MARK: - 外部输入

    func setStyle(_ s: StopoverStyle) {
        guard s != style else { return }
        style = s
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.mipFilter = .linear
        m.diffuse.wrapS = .repeat
        switch s {
        case .marble:
            m.diffuse.contents = UIImage(named: "stopover_marble.jpg")
            scene.background.contents = UIImage(named: "stopover_sky.jpg")
        case .night:
            m.diffuse.contents = UIImage(named: "stopover_night.jpg")
            m.lightingModel = .constant   // 夜光图本来就是暗的,再打光就看不见了
            scene.background.contents = UIColor(hex: 0x030407)
        case .paper:
            m.lightingModel = .constant
            m.diffuse.contents = PaperMap.shared.image ?? UIColor(hex: 0xdfe6ea)
            scene.background.contents = UIColor(hex: 0xE6E2DA)
            if PaperMap.shared.image == nil {
                PaperMap.shared.render { [weak self] img in
                    guard self?.style == .paper else { return }
                    self?.earth.geometry?.firstMaterial?.diffuse.contents = img
                }
            }
        }
        earth.geometry?.materials = [m]

        if let a = s.atmosphere {
            halo.isHidden = false
            let hm = SCNMaterial()
            hm.lightingModel = .constant
            hm.diffuse.contents = Self.haloImage(a)
            hm.blendMode = .add
            hm.writesToDepthBuffer = false
            hm.isDoubleSided = true
            halo.geometry?.materials = [hm]
        } else {
            halo.isHidden = true
        }
        if let mk = marks { rebuildMarks(mk) }
        labelFor.values.forEach { $0.removeFromSuperview() }
        spare.forEach { $0.removeFromSuperview() }
        labelFor = [:]; spare = []
        lastLabelKey = ""
        view.setNeedsDisplay()
    }

    func setMarks(_ m: StopoverMarks) {
        guard m != marks else { return }
        marks = m
        rebuildMarks(m)
    }

    // MARK: 城名(放大后): UIKit 小标签盖在 SCNView 上,每帧投影 + 贪心避让。

    struct Place: Equatable { let id: String; let name: String; let lat: Double; let lng: Double; let rank: Int }
    /// 预先算好: 球面坐标 + 字宽(字宽每帧量很贵)
    private struct Prepared { let place: Place; let v: SIMD3<Float>; let width: CGFloat }
    private var places: [Prepared] = []
    /// 每座城固定一个标签(id → label): 只挪 frame,不改字就不重画
    private var labelFor: [String: UILabel] = [:]
    private var spare: [UILabel] = []
    private var lastLabelKey = ""
    private static let fontBold = UIFont(name: "STSongti-SC-Bold", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold)
    private static let fontReg = UIFont(name: "STSongti-SC-Regular", size: 11.5) ?? .systemFont(ofSize: 11.5)

    func setPlaces(_ p: [Place]) {
        guard p.count != places.count else { return }
        places = p.sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }.map { pl in
            let v = Self.position(lat: pl.lat, lng: pl.lng, alt: 1)
            let f = pl.rank == 0 ? Self.fontBold : Self.fontReg
            return Prepared(place: pl, v: SIMD3(v.x, v.y, v.z), width: ceil((pl.name as NSString).size(withAttributes: [.font: f]).width) + 8)
        }
        labelFor.values.forEach { $0.removeFromSuperview() }
        labelFor = [:]; spare = []
        layoutLabels(force: true)
    }

    /// 视距门槛: 来过的 < 2.6;有资料的 < 1.9;没资料的 < 1.5。正面、屏幕内、不打架才摆,最多 60 个。
    /// 现在: 变换矩阵一帧取一次自己乘;投影只对过了门槛的做;阴影画进字里(NSShadow),只在建标签时画一次
    private func layoutLabels(force: Bool = false) {
        let key = String(format: "%.4f|%.3f|%.3f|%.3f|%@", distance, centerLat, centerLng, camShift, style?.rawValue ?? "")
        guard force || key != lastLabelKey else { return }
        lastLabelKey = key
        let limits: [Double] = [2.6, 1.9, 1.5]
        let b = view.bounds
        let bounds = CGRect(x: b.minX + 6, y: b.minY + 112, width: b.width - 12, height: b.height - 112 - 150)
        var keep: Set<String> = []
        if distance < limits[0] || focus != nil {
            // 投影自己算: view.projectPoint 要跟渲染线程抢锁,一帧几百次主线程就卡
            let vs = view.bounds.size
            guard vs.width > 0, let cam = camera.camera else { return }
            let proj = simd_float4x4(cam.projectionTransform(withViewportSize: vs))
            let m = proj * camera.presentation.simdWorldTransform.inverse * earth.presentation.simdWorldTransform
            let c = Self.position(lat: centerLat, lng: centerLng, alt: 1)
            let cv = SIMD3<Float>(c.x, c.y, c.z)
            var taken: [CGRect] = []
            let focusID = focus.flatMap { f in places.first { abs($0.place.lat - f.x) < 1e-6 && abs($0.place.lng - f.y) < 1e-6 }?.place.id }
            let ordered = focusID.flatMap { id in places.firstIndex { $0.place.id == id } }.map { [places[$0]] + places } ?? places
            for pr in ordered where keep.count < 60 {
                guard !keep.contains(pr.place.id) else { continue }
                let isFocus = pr.place.id == focusID
                guard isFocus || distance < limits[min(pr.place.rank, 2)] else { continue }
                guard simd_dot(pr.v, cv) > 0.35 else { continue }
                let c4 = m * SIMD4(pr.v, 1)
                guard c4.w > 0 else { continue }
                let sx = CGFloat((c4.x / c4.w + 1) / 2) * vs.width, sy = CGFloat((1 - c4.y / c4.w) / 2) * vs.height
                let r = CGRect(x: sx - pr.width / 2, y: sy - 22, width: pr.width, height: 17)
                guard bounds.contains(r), !taken.contains(where: { $0.insetBy(dx: -3, dy: -2).intersects(r) }) else { continue }
                taken.append(r)
                keep.insert(pr.place.id)
                let l = labelFor[pr.place.id] ?? makeLabel(pr.place)
                labelFor[pr.place.id] = l
                if l.frame != r { l.frame = r }
                l.isHidden = false
            }
        }
        for (id, l) in labelFor where !keep.contains(id) {
            l.isHidden = true
            labelFor[id] = nil
            spare.append(l)
        }
    }

    private func makeLabel(_ p: Place) -> UILabel {
        let l = spare.popLast() ?? {
            let x = UILabel()
            x.textAlignment = .center
            x.isUserInteractionEnabled = false
            view.addSubview(x)
            return x
        }()
        let dark = style?.isDark ?? true
        let sh = NSShadow()
        sh.shadowColor = dark ? UIColor.black : UIColor(hex: 0xE6E2DA)
        sh.shadowBlurRadius = 3
        sh.shadowOffset = .zero
        l.attributedText = NSAttributedString(string: p.name, attributes: [
            .font: p.rank == 0 ? Self.fontBold : Self.fontReg,
            .foregroundColor: dark ? UIColor(white: 1, alpha: p.rank == 0 ? 1 : 0.85)
                                   : UIColor(hex: 0x1F2A38).withAlphaComponent(p.rank == 0 ? 1 : 0.8),
            .shadow: sh])
        return l
    }

    private var kick = 0
    func setKick(_ k: Int) {
        guard k != kick else { return }
        kick = k
        fly(toLat: centerLat * 0.3, lng: centerLng + 200, dist: Self.maxDist * 0.85, dur: 0.9)
    }

    func setFocus(_ f: SIMD2<Double>?) {
        guard f != focus else { return }
        focus = f
        lastLabelKey = ""
        focusRing.childNodes.forEach { $0.removeFromParentNode() }
        guard let f, let style else { return }
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.02, pipeRadius: 0.0014))
        ring.geometry?.firstMaterial = Self.glowMaterial(style.isDark ? .white : style.pin)
        let p = Self.position(lat: f.x, lng: f.y, alt: 1.004)
        let holder = SCNNode()
        holder.position = p
        focusRing.addChildNode(holder)
        ring.look(at: SCNVector3(p.x, p.y, p.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        let pulse = CABasicAnimation(keyPath: "scale")
        pulse.fromValue = SCNVector3(0.8, 0.8, 0.8)
        pulse.toValue = SCNVector3(1.25, 1.25, 1.25)
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        ring.addAnimation(pulse, forKey: "pulse")
        holder.addChildNode(ring)
        // 飞过去拉近到能看清城名那档
        fly(toLat: f.x, lng: f.y, dist: min(distance, 1.55))
    }

    // MARK: - 摆点、连线、星星、城名

    private func rebuildMarks(_ m: StopoverMarks) {
        guard let style else { return }
        marksNode.childNodes.forEach { $0.removeFromParentNode() }
        labelsNode.childNodes.forEach { $0.removeFromParentNode() }
        labelNodes = []
        arcMats = []

        let dotMat = Self.glowMaterial(style.isDark ? UIColor(hex: 0xfff1ee) : style.pin)
        let haloImg = Self.dotGlow(style.pin)
        for p in m.pins {
            let n = SCNNode()
            n.position = Self.position(lat: p.lat, lng: p.lng, alt: 1.002)
            let dot = SCNNode(geometry: SCNSphere(radius: 0.0055))
            dot.geometry?.firstMaterial = dotMat
            n.addChildNode(dot)
            let g = SCNNode(geometry: SCNPlane(width: 0.05, height: 0.05))
            let gm = SCNMaterial()
            gm.lightingModel = .constant
            gm.diffuse.contents = haloImg
            gm.blendMode = style.isDark ? .add : .alpha
            gm.writesToDepthBuffer = false
            g.geometry?.firstMaterial = gm
            g.constraints = [SCNBillboardConstraint()]
            n.addChildNode(g)
            n.name = "pin"
            marksNode.addChildNode(n)

            let label = SCNNode(geometry: SCNPlane(width: 1, height: 1))
            let img = Self.labelImage(p.count > 1 ? "\(p.name) ×\(p.count)" : p.name, color: style.label, shadow: style.isDark)
            label.geometry = SCNPlane(width: img.size.width / img.size.height * 0.046, height: 0.046)
            let lm = SCNMaterial()
            lm.lightingModel = .constant
            lm.diffuse.contents = img
            lm.writesToDepthBuffer = false
            label.geometry?.firstMaterial = lm
            label.position = Self.position(lat: p.lat, lng: p.lng, alt: 1.012)
            label.pivot = SCNMatrix4MakeTranslation(0, -0.032, 0)
            label.constraints = [SCNBillboardConstraint()]
            label.opacity = 0
            _ = label   // 城名改走 UIKit 小标签(layoutLabels),3D 字不再挂
        }

        let arcMat = Self.glowMaterial(style.arc)
        let arcGlow = Self.glowMaterial(style.arc.withAlphaComponent(style.isDark ? 0.28 : 0.18))
        arcGlow.blendMode = style.isDark ? .add : .alpha
        arcGlow.writesToDepthBuffer = false
        // 流星: 一串高斯软光点沿线跑,头大头亮,往后一颗比一颗小、比一颗淡

        let headImg = Self.softDot(style.isDark ? .white : style.pin, core: true)
        let tailImg = Self.softDot(style.isDark ? style.arc : style.pin, core: false)
        let blend: SCNBlendMode = style.isDark ? .add : .alpha
        comets = []
        twinkles = []
        for (i, a) in m.arcs.enumerated() {
            let pts = Self.arcPoints(a.from, a.to)
            guard pts.count > 1 else { continue }
            let core = SCNNode(geometry: Self.tube(pts, radius: 0.0016, material: arcMat))
            let glow = SCNNode(geometry: Self.tube(pts, radius: 0.0055, material: arcGlow))
            if arcMats.isEmpty { arcMats = [(arcMat, 0.0016), (arcGlow, 0.0055)] }
            var sprites: [SCNNode] = []
            for k in 0..<Self.cometDots {
                let n = SCNNode(geometry: SCNPlane(width: 0.034, height: 0.034))
                let mt = SCNMaterial()
                mt.lightingModel = .constant
                mt.diffuse.contents = k == 0 ? headImg : tailImg
                mt.blendMode = blend
                mt.writesToDepthBuffer = false
                n.geometry?.firstMaterial = mt
                n.constraints = [SCNBillboardConstraint()]
                n.renderingOrder = 6
                n.isHidden = true
                marksNode.addChildNode(n)
                sprites.append(n)
            }
            // 每条线起跑时间错开(按序号撒开,不用随机: 重摆时不跳)
            comets.append(Comet(pts: pts.map { SIMD3($0.x, $0.y, $0.z) }, sprites: sprites,
                                offset: Double(i) * 0.6180339))
            glow.renderingOrder = 5
            marksNode.addChildNode(core)
            marksNode.addChildNode(glow)
        }

        for s in m.stars {
            let n = SCNNode(geometry: SCNPlane(width: 0.075, height: 0.075))   // larger canvas so the twinkle can bloom; the star itself is the same size
            let sm = SCNMaterial()
            sm.lightingModel = .constant
            sm.diffuse.contents = Self.starImage(s.hers && s.his ? [style.star, style.star2] : [s.hers ? style.star : style.star2])
            sm.writesToDepthBuffer = false
            n.geometry?.firstMaterial = sm
            n.position = Self.position(lat: s.lat, lng: s.lng, alt: 1.01)
            n.name = "pin"   // scales with zoom like the dots
            n.renderingOrder = 7
            n.constraints = [SCNBillboardConstraint()]
            // Twinkle brighter, never dimmer (a dimmed star vanishes when zoomed out): an additive white star on top
            let fm = SCNMaterial()
            fm.lightingModel = .constant
            fm.diffuse.contents = Self.starImage([.white])
            fm.writesToDepthBuffer = false
            fm.blendMode = .add
            let flash = SCNNode(geometry: SCNPlane(width: 0.075, height: 0.075))
            flash.geometry?.firstMaterial = fm
            flash.renderingOrder = 8
            n.addChildNode(flash)
            twinkles.append((flash, .random(in: 0...(2 * .pi)), .random(in: 1.6...2.6)))
            marksNode.addChildNode(n)
        }
        apply()
    }

    // MARK: - 手势

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        lastTouch = Date()
        flight = nil
        let k = 0.12 * (distance - 1)    // 越近转得越慢,指尖下的地面大致跟手
        let t = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        centerLng -= t.x * k
        centerLat = min(85, max(-85, centerLat + t.y * k))
        if g.state == .ended {
            let v = g.velocity(in: view)
            velocity = SIMD2(-v.x * k / 60, v.y * k / 60)
        } else {
            velocity = .zero
        }
        apply()
    }

    private var pinchStart = 0.0
    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        lastTouch = Date()
        flight = nil
        if g.state == .began { pinchStart = distance }
        // 按到地面的高度缩放,而不是到球心,贴近地面时才不会一下就撞进去
        let alt = (pinchStart - 1) / Double(g.scale)
        distance = min(Self.maxDist, max(Self.minDist, 1 + alt))
        apply()
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        lastTouch = Date()
        velocity = .zero
        let hits = view.hitTest(g.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        guard let hit = hits.first(where: { $0.node === earth }) else { return }
        let p = hit.localCoordinates
        let lat = asin(Double(max(-1, min(1, p.y)))) * 180 / .pi
        let lng = atan2(Double(p.x), Double(p.z)) * 180 / .pi
        onTap?(lat, lng, distance)
    }

    @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
        lastTouch = Date()
        let hits = view.hitTest(g.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        guard let hit = hits.first(where: { $0.node === earth }) else { return }
        let p = hit.localCoordinates
        fly(toLat: asin(Double(p.y)) * 180 / .pi, lng: atan2(Double(p.x), Double(p.z)) * 180 / .pi,
            dist: max(Self.minDist, 1 + (distance - 1) * 0.5))
    }

    private func fly(toLat lat: Double, lng: Double, dist: Double, dur: Double = 1.1) {
        var to = lng
        if dur < 1 { to = lng } else {   // 骰子甩开那一下就是要转过去半圈多,别就近折回
            while to - centerLng > 180 { to -= 360 }
            while to - centerLng < -180 { to += 360 }
        }
        velocity = .zero
        flight = (SIMD3(centerLat, centerLng, distance), SIMD3(lat, to, dist), CACurrentMediaTime(), dur)
    }

    // MARK: - 每帧

    @objc private func tick() {
        var moved = false
        if let f = flight {
            let t = min(1, (CACurrentMediaTime() - f.start) / f.dur)
            let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            let v = f.from + (f.to - f.from) * e
            centerLat = v.x; centerLng = v.y; distance = v.z
            if t >= 1 { flight = nil; lastTouch = Date() }
            moved = true
        } else if simd_length(velocity) > 0.002 {
            centerLng += velocity.x
            centerLat = min(85, max(-85, centerLat + velocity.y))
            velocity *= 0.94
            moved = true
        } else if focus == nil, Date().timeIntervalSince(lastTouch) > 8 {
            // 8 秒没碰屏幕、也没选城: 慢慢自转
            centerLng += 0.05
            moved = true
        }
        let shiftTo = focus == nil ? 0.0 : -0.42 * (distance - 1) / 1.1
        if abs(camShift - shiftTo) > 0.0005 {
            camShift += (shiftTo - camShift) * 0.12
            moved = true
        }
        if moved { apply() }
        moveComets()
        let t = CACurrentMediaTime()
        for w in twinkles {
            let k = Float(0.5 + 0.5 * sin(t * 2 * .pi / w.period + w.phase))
            let f = k * k * k   // calm most of the time, a brief flash now and then
            w.node.opacity = CGFloat(0.85 * f)
            let sc = 1 + 0.3 * f
            w.node.scale = SCNVector3(sc, sc, sc)
        }
    }

    private func moveComets() {
        let now = CACurrentMediaTime() / cometPeriod
        let run = 0.58           // 一轮里有 58% 的时间在跑
        let gap = 0.022          // 相邻两颗沿线隔多远(占整条线)
        for c in comets {
            var ph = now + c.offset
            ph -= ph.rounded(.down)
            let head = ph / run * (1 + gap * Double(Self.cometDots))   // 尾巴也要跑出终点才算完
            for (k, n) in c.sprites.enumerated() {
                let u = head - gap * Double(k)
                guard u >= 0, u <= 1 else { n.isHidden = true; continue }
                n.isHidden = false
                let f = Float(u) * Float(c.pts.count - 1)
                let i = min(c.pts.count - 2, Int(f)), t = f - Float(i)
                let p = c.pts[i] + (c.pts[i + 1] - c.pts[i]) * t
                n.position = SCNVector3(p.x, p.y, p.z)
                let fall = 1 - Float(k) / Float(Self.cometDots)
                let sc = dotScale * (0.35 + 0.65 * fall)
                n.scale = SCNVector3(sc, sc, sc)
                n.opacity = CGFloat(pow(fall, 1.6))
            }
        }
    }

    private func apply() {
        camera.position = SCNVector3(0, Float(camShift), Float(distance))
        pitch.eulerAngles = SCNVector3(Float(centerLat * .pi / 180), 0, 0)
        yaw.eulerAngles = SCNVector3(0, Float(-centerLng * .pi / 180), 0)

        // 大气平面跟着视距放大: 透视下看到的球轮廓半径 = 1/√(1-1/d²)(折到球心那个平面上)
        let rs = 1 / sqrt(max(0.0001, 1 - 1 / (distance * distance)))
        halo.scale = SCNVector3(Float(rs * 1.32), Float(rs * 1.32), 1)

        // 点和城名按视距等比缩,屏幕上看着一样大
        let s = Float((distance - 1) / 2.2)
        let sv = SCNVector3(max(0.18, s), max(0.18, s), max(0.18, s))
        for n in marksNode.childNodes where n.name == "pin" { n.scale = sv }
        // 选中圈也跟着缩,拉近了不会罩住一大片
        for h in focusRing.childNodes { h.scale = SCNVector3(max(0.1, s), max(0.1, s), max(0.1, s)) }
        // 线不设下限,拉近了一直跟着细下去
        let arcScale = Float((distance - 1) / (3.5 - 1))
        dotScale = arcScale
        for (m, r) in arcMats { m.setValue(r * arcScale, forKey: "width") }
        let labelAlpha = CGFloat(max(0, min(1, (2.35 - distance) / 0.35)))
        let cam = Self.position(lat: centerLat, lng: centerLng, alt: 1)
        for n in labelNodes {
            n.scale = sv
            // 转到背面的不画: 跟屏幕正中的点夹角超过 70° 就隐掉,免得字从球边上翻过来
            let p = n.position
            let dot = p.x * cam.x + p.y * cam.y + p.z * cam.z
            n.opacity = labelAlpha * CGFloat(max(0, min(1, (dot / 1.012 - 0.34) / 0.12)))
        }
        view.setNeedsDisplay()
        layoutLabels()
    }

    // MARK: - 几何

    static func position(lat: Double, lng: Double, alt: Double) -> SCNVector3 {
        let la = lat * .pi / 180, lo = lng * .pi / 180
        return SCNVector3(Float(alt * cos(la) * sin(lo)), Float(alt * sin(la)), Float(alt * cos(la) * cos(lo)))
    }

    private static func vec(_ ll: SIMD2<Double>) -> SIMD3<Double> {
        let la = ll.x * .pi / 180, lo = ll.y * .pi / 180
        return SIMD3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))
    }

    /// 大圆弧,中间抬起来,离得越远抬得越高
    static func arcPoints(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> [SCNVector3] {
        let p = vec(a), q = vec(b)
        let ang = acos(max(-1, min(1, simd_dot(p, q))))
        guard ang > 0.001 else { return [] }
        let lift = min(0.32, ang * 0.22)
        let n = max(16, Int(ang * 60))
        return (0...n).map { i in
            let t = Double(i) / Double(n)
            let v = (sin((1 - t) * ang) * p + sin(t * ang) * q) / sin(ang)
            let r = 1.002 + lift * sin(.pi * t)
            return SCNVector3(Float(v.x * r), Float(v.y * r), Float(v.z * r))
        }
    }

    /// 沿折线拼一根六棱细管(Metal 的线只有 1 像素,发光线得自己做成管子)
    static func tube(_ pts: [SCNVector3], radius: Float, material: SCNMaterial, uOffset: Double = 0) -> SCNGeometry {
        let sides = 6
        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], uvs: [CGPoint] = [], idx: [Int32] = []
        for (i, p) in pts.enumerated() {
            let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)]
            let t = simd_normalize(SIMD3(b.x - a.x, b.y - a.y, b.z - a.z))
            let up = simd_normalize(SIMD3(p.x, p.y, p.z))
            let u = simd_normalize(simd_cross(t, up)), w = simd_cross(u, t)
            for s in 0..<sides {
                let th = Float(s) / Float(sides) * 2 * .pi
                let o = u * cos(th) + w * sin(th)
                verts.append(p)
                norms.append(SCNVector3(o.x, o.y, o.z))
                // 一条线只占贴图周期的 0.6: 流星跑完一趟有一小段空档再来
                uvs.append(CGPoint(x: uOffset + Double(i) / Double(pts.count - 1) * 0.6, y: 0.5))
            }
        }
        for i in 0..<(pts.count - 1) {
            for s in 0..<sides {
                let a = Int32(i * sides + s), b = Int32(i * sides + (s + 1) % sides)
                let c = a + Int32(sides), d = b + Int32(sides)
                idx += [a, c, b, b, c, d]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms), SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        material.shaderModifiers = [.geometry: """
            #pragma arguments
            float width;
            #pragma body
            _geometry.position.xyz += _geometry.normal * width;
            """]
        material.setValue(radius, forKey: "width")
        g.materials = [material]
        return g
    }

    /// 经纬网格球,UV 按等距圆柱: u = (经度+180)/360,v = (90-纬度)/180
    static func sphere() -> SCNGeometry {
        let cols = 144, rows = 72
        var v: [SCNVector3] = [], n: [SCNVector3] = [], uv: [CGPoint] = [], idx: [Int32] = []
        for r in 0...rows {
            let lat = 90 - Double(r) / Double(rows) * 180
            for c in 0...cols {
                let lng = Double(c) / Double(cols) * 360 - 180
                let p = position(lat: lat, lng: lng, alt: 1)
                v.append(p); n.append(p)
                uv.append(CGPoint(x: Double(c) / Double(cols), y: Double(r) / Double(rows)))
            }
        }
        for r in 0..<rows {
            for c in 0..<cols {
                let a = Int32(r * (cols + 1) + c), b = a + 1
                let d = a + Int32(cols + 1), e = d + 1
                idx += [a, d, b, b, d, e]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n),
                                     SCNGeometrySource(textureCoordinates: uv)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    // MARK: - 小图

    static func glowMaterial(_ c: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c
        return m
    }

    /// 大气: 球轮廓(半径 1/1.32)往外一圈光晕,往外淡掉
    static func haloImage(_ c: UIColor) -> UIImage {
        let size = CGSize(width: 512, height: 512)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let r0 = 256 / 1.32
            // 贴着球边最亮,往外按指数淡掉
            let stops: [(CGFloat, CGFloat)] = [(0.97, 0.42), (1.0, 0.42), (1.015, 0.3), (1.035, 0.19),
                                                (1.06, 0.1), (1.09, 0.045), (1.13, 0.015), (1.18, 0)]
            let colors = stops.map { c.withAlphaComponent($0.1).cgColor } as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                               locations: stops.map { $0.0 * CGFloat(r0) / 256 })!
            cg.drawRadialGradient(g, startCenter: CGPoint(x: 256, y: 256), startRadius: 0,
                                  endCenter: CGPoint(x: 256, y: 256), endRadius: 256, options: [])
        }
    }

    /// 高斯软光点;头那颗中间多一粒白芯
    static func softDot(_ c: UIColor, core: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            let stops: [(CGFloat, CGFloat)] = core
                ? [(0, 1), (0.12, 0.95), (0.3, 0.45), (0.55, 0.12), (1, 0)]
                : [(0, 0.8), (0.25, 0.45), (0.5, 0.15), (1, 0)]
            let colors = stops.map { c.withAlphaComponent($0.1).cgColor } as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: stops.map(\.0))!
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                             endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
    }

    static func dotGlow(_ c: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            let colors = [c.withAlphaComponent(0.85).cgColor, c.withAlphaComponent(0.35).cgColor,
                          c.withAlphaComponent(0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.3, 1])!
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                             endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
    }

    /// Round, soft star; both want to go = left half gold, right half blue
    static func starImage(_ colors: [UIColor]) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180)).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: 42, y: 42)
            let path = UIBezierPath()
            for i in 0..<10 {
                let r: CGFloat = i % 2 == 0 ? 40 : 21
                let a = CGFloat(i) * .pi / 5 - .pi / 2
                let p = CGPoint(x: 48 + r * cos(a), y: 50 + r * sin(a))
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.close()
            cg.setLineJoin(.round)
            cg.setShadow(offset: .zero, blur: 8, color: colors[0].withAlphaComponent(0.8).cgColor)
            for (i, c) in colors.enumerated() {
                cg.saveGState()
                if colors.count == 2 { cg.clip(to: CGRect(x: i == 0 ? 0 : 48, y: 0, width: 48, height: 96)) }
                c.setFill(); c.setStroke()
                path.lineWidth = 9
                path.fill(); path.stroke()
                cg.restoreGState()
            }
        }
    }

    static func labelImage(_ text: String, color: UIColor, shadow: Bool) -> UIImage {
        let font = UIFont(name: "Songti SC Bold", size: 30) ?? .systemFont(ofSize: 30, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let sz = (text as NSString).size(withAttributes: attrs)
        let size = CGSize(width: ceil(sz.width) + 16, height: ceil(sz.height) + 10)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            if shadow { ctx.cgContext.setShadow(offset: .zero, blur: 5, color: UIColor.black.withAlphaComponent(0.9).cgColor) }
            (text as NSString).draw(at: CGPoint(x: 8, y: 5), withAttributes: attrs)
        }
    }
}

/// 旧图: 拿国界 GeoJSON 现画一张等距圆柱纸本地图(亚麻纸 + 海港蓝墨),画一次存进缓存
@MainActor
final class PaperMap {
    static let shared = PaperMap()
    private(set) var image: UIImage?
    private var waiting: [(UIImage) -> Void] = []

    nonisolated private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("stopover-paper-v1.jpg")
    }

    init() {
        if let d = try? Data(contentsOf: Self.cacheURL) { image = UIImage(data: d) }
    }

    func render(_ done: @escaping (UIImage) -> Void) {
        if let image { done(image); return }
        waiting.append(done)
        guard waiting.count == 1 else { return }
        Task.detached(priority: .userInitiated) {
            let img = Self.draw()
            if let d = img.jpegData(compressionQuality: 0.85) { try? d.write(to: Self.cacheURL) }
            await MainActor.run {
                self.image = img
                self.waiting.forEach { $0(img) }
                self.waiting = []
            }
        }
    }

    nonisolated private static func draw() -> UIImage {
        let W = 4096.0, H = 2048.0
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            let cg = ctx.cgContext
            UIColor(hex: 0xdfe6ea).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: W, height: H))
            // 经纬网: 每 15° 一道细线
            cg.setStrokeColor(UIColor(hex: 0x3F5F86).withAlphaComponent(0.16).cgColor)
            cg.setLineWidth(1.5)
            for i in stride(from: 0.0, through: 360, by: 15) { cg.move(to: CGPoint(x: i / 360 * W, y: 0)); cg.addLine(to: CGPoint(x: i / 360 * W, y: H)) }
            for i in stride(from: 0.0, through: 180, by: 15) { cg.move(to: CGPoint(x: 0, y: i / 180 * H)); cg.addLine(to: CGPoint(x: W, y: i / 180 * H)) }
            cg.strokePath()

            guard let url = Bundle.main.url(forResource: "stopover_countries", withExtension: "json"),
                  let d = try? Data(contentsOf: url),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            let path = CGMutablePath()
            func ring(_ r: [[Double]]) {
                for (i, p) in r.enumerated() where p.count >= 2 {
                    let pt = CGPoint(x: (p[0] + 180) / 360 * W, y: (90 - p[1]) / 180 * H)
                    i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                path.closeSubpath()
            }
            for f in j["features"] as? [[String: Any]] ?? [] {
                guard let g = f["geometry"] as? [String: Any], let type = g["type"] as? String else { continue }
                if type == "Polygon", let c = g["coordinates"] as? [[[Double]]] { c.forEach(ring) }
                if type == "MultiPolygon", let c = g["coordinates"] as? [[[[Double]]]] { c.forEach { $0.forEach(ring) } }
            }
            cg.addPath(path)
            cg.setFillColor(UIColor(hex: 0xddd2bb).cgColor)
            cg.fillPath(using: .evenOdd)
            cg.addPath(path)
            cg.setStrokeColor(UIColor(hex: 0x3F5F86).withAlphaComponent(0.85).cgColor)
            cg.setLineWidth(2.2)
            cg.setLineJoin(.round)
            cg.strokePath()
        }
    }
}
