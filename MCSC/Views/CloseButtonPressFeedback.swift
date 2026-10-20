import Cocoa
import QuartzCore

/// Created on the first hold. All motion stays on the symbol's layer, leaving
/// the button's frame and hit geometry unchanged.
@MainActor
final class CloseButtonPressFeedback {
    private enum Keys {
        static let fill = "mcsc.closeButtonPress.fill"
        static let opacity = "mcsc.closeButtonPress.opacity"
        static let rotation = "mcsc.closeButtonPress.rotation"
        static let translation = "mcsc.closeButtonPress.translation"
    }

    private struct Sample {
        var progress: CGFloat = 0
        var rotation: CGFloat = 0
        var translation: CGFloat = 0
        var rotationVelocity: CGFloat = 0
        var translationVelocity: CGFloat = 0
        var angularFrequency: Double = 18 * .pi
        var opacity: Float = 0
    }

    private enum Phase {
        case idle
        case holding(start: CFTimeInterval, duration: TimeInterval, initial: Sample)
        case returning(start: CFTimeInterval, initial: Sample)
    }

    private weak var imageLayer: CALayer?
    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let scale: CGFloat
    private let returnDuration: TimeInterval = 0.28
    private let fadeDuration: TimeInterval = 0.10
    private var phase: Phase = .idle

    init(container: NSView, imageView: NSImageView) {
        container.wantsLayer = true
        imageView.wantsLayer = true
        imageLayer = imageView.layer
        let bounds = container.bounds
        scale = max(0.5, min(bounds.width, bounds.height) / 32)
        let lineWidth = 2 * scale
        let radius = max(1, min(bounds.width, bounds.height) / 2 - lineWidth * 0.75)
        let startAngle: CGFloat = container.isFlipped ? -.pi / 2 : .pi / 2
        let direction: CGFloat = container.isFlipped ? 1 : -1
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY),
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: startAngle + direction * 2 * .pi,
                    clockwise: !container.isFlipped)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [track, progress] {
            layer.frame = bounds
            layer.contentsScale = container.window?.backingScaleFactor ?? container.layer?.contentsScale ?? 1
            layer.path = path
            layer.fillColor = nil
            layer.lineWidth = lineWidth
            layer.lineCap = .round
            layer.opacity = 0
            container.layer?.addSublayer(layer)
        }
        track.strokeColor = NSColor.white.withAlphaComponent(0.28).cgColor
        progress.strokeColor = NSColor.controlAccentColor.cgColor
        progress.strokeEnd = 0
        CATransaction.commit()
    }

    /// Delay is part of the complete hold duration. Core Animation schedules
    /// the visible portion without a timer or work item to cancel on release.
    func start(duration: TimeInterval, delay: TimeInterval = 0) {
        guard duration.isFinite, duration > 0, delay.isFinite else { reset(); return }
        let delay = min(duration, max(0, delay))
        let remainingDuration = duration - delay
        guard remainingDuration > 0 else { reset(); return }
        let now = CACurrentMediaTime()
        let initial = delay > 0 ? Sample() : currentSample(at: now)
        let beginTime = now + delay
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        removeOwnAnimations()
        phase = .holding(start: beginTime, duration: remainingDuration, initial: initial)
        setRingModel(progress: 1, opacity: 1)

        let fill = CABasicAnimation(keyPath: "strokeEnd")
        fill.fromValue = initial.progress
        fill.toValue = 1
        fill.duration = remainingDuration
        fill.beginTime = progress.convertTime(beginTime, from: nil)
        fill.fillMode = .backwards
        fill.timingFunction = CAMediaTimingFunction(name: .linear)
        progress.add(fill, forKey: Keys.fill)
        animateOpacity(
            from: initial.opacity,
            to: 1,
            duration: min(fadeDuration, remainingDuration),
            beginTime: beginTime
        )
        animateMotion(duration: remainingDuration, initial: initial, returning: false, beginTime: beginTime)
    }

    /// Retraction is visual only; the owner decides whether a hold activated.
    func release() {
        guard case let .holding(start, _, _) = phase else { return }
        let now = CACurrentMediaTime()
        guard now >= start else { reset(); return }
        let initial = currentSample(at: now)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        removeOwnAnimations()
        phase = .returning(start: now, initial: initial)
        setRingModel(progress: 0, opacity: 0)

        let fill = CABasicAnimation(keyPath: "strokeEnd")
        fill.fromValue = initial.progress
        fill.toValue = 0
        fill.duration = returnDuration
        fill.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        progress.add(fill, forKey: Keys.fill)
        // Keep the track visible until both the ring and shake return to rest.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [initial.opacity, initial.opacity, 0]
        fade.keyTimes = [0, NSNumber(value: returnDuration / (returnDuration + fadeDuration)), 1]
        fade.duration = returnDuration + fadeDuration
        fade.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
        track.add(fade, forKey: Keys.opacity)
        progress.add(fade, forKey: Keys.opacity)
        animateMotion(duration: returnDuration, initial: initial, returning: true)
    }

    /// Call on exit/reentry. Other hover, appearance, and symbol animations
    /// retain their own keys and model transforms.
    func reset() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        removeOwnAnimations()
        phase = .idle
        setRingModel(progress: 0, opacity: 0)
    }

    private func currentSample(at time: CFTimeInterval) -> Sample {
        // A previous frame's presentation tree can survive until the next
        // commit after reset; a fresh entry must still begin at zero.
        if case .idle = phase {
            return Sample()
        }
        var sample: Sample
        switch phase {
        case .idle:
            sample = Sample()
        case let .holding(start, duration, initial):
            let elapsed = max(0, time - start)
            let t = min(1, elapsed / duration)
            sample = motionSample(t: t, elapsed: elapsed, duration: duration, initial: initial, returning: false)
            sample.progress = initial.progress + (1 - initial.progress) * t
            sample.opacity = initial.opacity + (1 - initial.opacity) * Float(min(1, elapsed / fadeDuration))
        case let .returning(start, initial):
            let elapsed = max(0, time - start)
            let t = min(1, elapsed / returnDuration)
            sample = motionSample(t: t, elapsed: elapsed, duration: returnDuration, initial: initial, returning: true)
            sample.progress = initial.progress * (1 - smoothStep(t))
            sample.opacity = initial.opacity * Float(1 - min(1, max(0, elapsed - returnDuration) / fadeDuration))
        }
        // Presentation state keeps interruptions smooth. The analytical values
        // above also cover release before the first Core Animation commit.
        if let presentation = progress.presentation() {
            sample.progress = presentation.strokeEnd
            sample.opacity = presentation.opacity
        }
        if let imageLayer, let presentation = imageLayer.presentation() {
            sample.rotation = component("transform.rotation.z", of: presentation)
                - component("transform.rotation.z", of: imageLayer)
            sample.translation = component("transform.translation.x", of: presentation)
                - component("transform.translation.x", of: imageLayer)
        }
        return sample
    }

    private func animateMotion(duration: TimeInterval, initial: Sample, returning: Bool,
                               beginTime: CFTimeInterval? = nil) {
        guard let imageLayer else { return }
        let count = max(16, Int(ceil(duration * 60)))
        var rotations: [CGFloat] = []
        var translations: [CGFloat] = []
        rotations.reserveCapacity(count + 1)
        translations.reserveCapacity(count + 1)
        for index in 0 ... count {
            let t = Double(index) / Double(count)
            let sample = motionSample(
                t: t,
                elapsed: t * duration,
                duration: duration,
                initial: initial,
                returning: returning
            )
            rotations.append(sample.rotation)
            translations.append(sample.translation)
        }
        for (path, values, key) in [
            ("transform.rotation.z", rotations, Keys.rotation),
            ("transform.translation.x", translations, Keys.translation)
        ] {
            let animation = CAKeyframeAnimation(keyPath: path)
            animation.values = values
            animation.duration = duration
            animation.isAdditive = true
            animation.calculationMode = .cubic
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            if let beginTime {
                animation.beginTime = imageLayer.convertTime(beginTime, from: nil)
                animation.fillMode = .backwards
            }
            imageLayer.add(animation, forKey: key)
        }
    }

    private func motionSample(t: Double, elapsed: TimeInterval, duration: TimeInterval,
                              initial: Sample, returning: Bool) -> Sample {
        if returning {
            let frequency = max(20, initial.angularFrequency)
            let rotation = returnComponent(displacement: initial.rotation, velocity: initial.rotationVelocity,
                                           frequency: frequency, elapsed: elapsed, t: t, limit: 0.05)
            let translation = returnComponent(displacement: initial.translation, velocity: initial.translationVelocity,
                                              frequency: frequency, elapsed: elapsed, t: t, limit: 0.35 * scale)
            return Sample(rotation: rotation.displacement, translation: translation.displacement,
                          rotationVelocity: rotation.velocity, translationVelocity: translation.velocity,
                          angularFrequency: frequency)
        }
        let rampTime = min(1, elapsed / 0.16)
        let ramp = smoothStep(rampTime)
        let rampVelocity = 6 * rampTime * (1 - rampTime) / 0.16
        let envelope = ramp * (0.15 + 0.85 * t)
        let envelopeVelocity = rampVelocity * (0.15 + 0.85 * t) + ramp * 0.85 / duration
        // Preserve the same nine cycles per second when the visible portion
        // is shortened by a tap grace period.
        let frequency = 18 * Double.pi
        let wave = sin(frequency * min(elapsed, duration))
        let waveVelocity = frequency * cos(frequency * min(elapsed, duration))
        let velocity = envelopeVelocity * wave + envelope * waveVelocity
        return Sample(rotation: initial.rotation * (1 - ramp) + 0.05 * envelope * wave,
                      translation: initial.translation * (1 - ramp) + 0.35 * scale * envelope * wave,
                      rotationVelocity: t < 1 ? -initial.rotation * rampVelocity + 0.05 * velocity : 0,
                      translationVelocity: t < 1 ? -initial.translation * rampVelocity + 0.35 * scale * velocity : 0,
                      angularFrequency: frequency)
    }

    /// Match both position and velocity, including a release at a zero crossing.
    /// The smooth window ends at zero position and velocity without a final snap.
    private func returnComponent(displacement: CGFloat, velocity: CGFloat, frequency: Double,
                                 elapsed: TimeInterval, t: Double, limit: CGFloat)
        -> (displacement: CGFloat, velocity: CGFloat) {
        let damping = 10.0
        let sineCoefficient = (velocity + damping * displacement) / frequency
        let cosine = cos(frequency * elapsed)
        let sine = sin(frequency * elapsed)
        let oscillation = displacement * cosine + sineCoefficient * sine
        let oscillationVelocity = frequency * (-displacement * sine + sineCoefficient * cosine)
        let window = 1 - smoothStep(t)
        let windowVelocity = -6 * t * (1 - t) / returnDuration
        let decay = exp(-damping * elapsed)
        let value = decay * window * oscillation
        let boundedValue = min(limit, max(-limit, value))
        let speed = decay * ((windowVelocity - damping * window) * oscillation + window * oscillationVelocity)
        return (boundedValue, boundedValue == value ? speed : 0)
    }

    private func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    private func component(_ path: String, of layer: CALayer) -> CGFloat {
        (layer.value(forKeyPath: path) as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
    }

    private func animateOpacity(from: Float, to: Float, duration: TimeInterval, beginTime: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.fillMode = .backwards
        for layer in [track, progress] {
            animation.beginTime = layer.convertTime(beginTime, from: nil)
            layer.add(animation, forKey: Keys.opacity)
        }
    }

    private func setRingModel(progress value: CGFloat, opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress.strokeEnd = value
        progress.opacity = opacity
        track.opacity = opacity
        CATransaction.commit()
    }

    private func removeOwnAnimations() {
        progress.removeAnimation(forKey: Keys.fill)
        for layer in [track, progress] {
            layer.removeAnimation(forKey: Keys.opacity)
        }
        imageLayer?.removeAnimation(forKey: Keys.rotation)
        imageLayer?.removeAnimation(forKey: Keys.translation)
    }
}
