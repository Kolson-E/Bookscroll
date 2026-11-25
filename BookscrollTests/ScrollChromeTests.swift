import XCTest
@testable import Bookscroll

/// The motion of the feed's bars as they hide and come back (`ScrollChromeMotion`).
final class ScrollChromeTests: XCTestCase {
    /// An iPhone's bars: a 44-point navigation bar and an 83-point tab bar (with its shadow room).
    private func iPhone() -> ScrollChromeMotion {
        ScrollChromeMotion(navigationDistance: 44, tabDistance: 83 + ScrollChromeMotion.tabShadowRoom)
    }

    func testTheBarsMovePointForPointWithTheContent() {
        var motion = iPhone()
        XCTAssertTrue(motion.isShown)
        for step in 1...5 {
            motion.scroll(by: 10)
            XCTAssertEqual(motion.tabOffset, CGFloat(step * 10), "The tab bar moves exactly as far as the content")
        }
        XCTAssertEqual(motion.navigationOffset, 44, "The navigation bar is fully up after its own height")
        XCTAssertEqual(motion.navigationAlpha, 0)
        motion.scroll(by: -20)
        XCTAssertEqual(motion.tabOffset, 30)
        XCTAssertEqual(motion.navigationOffset, 30)
        XCTAssertEqual(motion.navigationAlpha, 1 - 30.0 / 44, accuracy: 0.0001)
        XCTAssertFalse(motion.isShown)
        XCTAssertFalse(motion.isHidden)
    }

    func testTheBarsStopAtEachEnd() {
        var motion = iPhone()
        motion.scroll(by: 200)
        XCTAssertEqual(motion.hidden, motion.fullDistance)
        XCTAssertEqual(motion.tabOffset, 99)
        XCTAssertTrue(motion.isHidden)
        motion.scroll(by: 40)
        XCTAssertEqual(motion.hidden, 99, "Reading on keeps them hidden")
        motion.scroll(by: -200)
        XCTAssertEqual(motion.hidden, 0)
        XCTAssertTrue(motion.isShown)
    }

    func testJumpsAndBadValuesDoNotMoveTheBars() {
        var motion = iPhone()
        motion.scroll(by: 30)
        for jump in [ScrollChromeMotion.largestStep + 1, -900, .nan, .infinity, -.infinity] {
            XCTAssertFalse(motion.scroll(by: jump), "\(jump) is not scrolling")
            XCTAssertEqual(motion.hidden, 30)
        }
        XCTAssertTrue(motion.scroll(by: ScrollChromeMotion.largestStep), "A fast flick still counts")
    }

    /// Thousands of random drags, flicks and jumps: the bars never move faster than the
    /// content, and never leave their range.
    func testTheTabBarNeverMovesFasterThanTheContent() {
        var generator = SeededGenerator(seed: 2026)
        var motion = iPhone()
        for _ in 0..<20_000 {
            let delta: CGFloat
            switch Int.random(in: 0..<10, using: &generator) {
            case 0: delta = CGFloat.random(in: -600...600, using: &generator)
            case 1...3: delta = CGFloat.random(in: -2...2, using: &generator)
            default: delta = CGFloat.random(in: -120...120, using: &generator)
            }
            let tab = motion.tabOffset
            let navigation = motion.navigationOffset
            let counted = motion.scroll(by: delta)
            XCTAssertLessThanOrEqual(abs(motion.tabOffset - tab), abs(delta) + 0.0001)
            XCTAssertLessThanOrEqual(abs(motion.navigationOffset - navigation), abs(delta) + 0.0001)
            if !counted { XCTAssertEqual(motion.tabOffset, tab, "A jump moves nothing") }
            XCTAssertTrue((0...motion.fullDistance).contains(motion.hidden))
            XCTAssertTrue((0...1).contains(motion.navigationAlpha))
            if delta > 0 && counted { XCTAssertGreaterThanOrEqual(motion.tabOffset, tab, "Reading down never brings the bar back") }
            if delta < 0 && counted { XCTAssertLessThanOrEqual(motion.tabOffset, tab, "Scrolling up never hides the bar") }
        }
    }

    func testAStoppedScrollRestsAtTheNearerEnd() {
        var motion = iPhone()
        let far: CGFloat = 1000
        XCTAssertEqual(motion.restingPoint(distanceFromTop: far), 0, "Shown stays shown")
        motion.place(49)
        XCTAssertEqual(motion.restingPoint(distanceFromTop: far), 0, "Less than half way: back")
        motion.place(50)
        XCTAssertEqual(motion.restingPoint(distanceFromTop: far), 99, "Half way or more: away")
        motion.place(99)
        XCTAssertEqual(motion.restingPoint(distanceFromTop: far), 99)
        XCTAssertEqual(motion.restingPoint(distanceFromTop: 60), 0, "Near the top they always show")
    }

    /// The ease to an end, from every start, at 30, 60 and 120 frames per second: no
    /// overshoot, no turning back, no fast jumps, there in about a quarter second, exactly.
    func testTheEaseIsSmoothAndEndsExactly() {
        let fastest = 99 / CGFloat(ScrollChromeMotion.settleTimeConstant) + ScrollChromeMotion.smallestSettleStep * 120
        for fps in [30.0, 60.0, 120.0] {
            let dt = 1 / fps
            for start in stride(from: CGFloat(0), through: 99, by: 1) {
                for target in [CGFloat(0), 99] {
                    var motion = iPhone()
                    motion.place(start)
                    var time = 0.0
                    var done = abs(start - target) <= 0.5
                    if done { motion.settle(toward: target, dt: dt) }
                    while !done {
                        let before = motion.hidden
                        done = motion.settle(toward: target, dt: dt)
                        time += dt
                        let step = motion.hidden - before
                        XCTAssertFalse(step != 0 && (step > 0) != (target > before), "The ease never turns back")
                        XCTAssertLessThanOrEqual(abs(target - motion.hidden), abs(target - before), "No overshoot")
                        XCTAssertLessThanOrEqual(abs(step) / CGFloat(dt), fastest, "No jump")
                        if time > 1 { break }
                    }
                    XCTAssertTrue(done)
                    XCTAssertEqual(motion.hidden, target, "Exactly at the end")
                    XCTAssertLessThanOrEqual(time, 0.4, "From \(start) to \(target) at \(fps) fps")
                }
            }
        }
    }

    func testALateFrameNeverOvershoots() {
        var motion = iPhone()
        motion.place(80)
        for dt in [0.5, 0.0, -1, .nan, 0.2] {
            let before = motion.hidden
            motion.settle(toward: 0, dt: dt)
            XCTAssertLessThanOrEqual(motion.hidden, before)
            XCTAssertGreaterThanOrEqual(motion.hidden, 0)
        }
    }

    func testAScrollDuringTheEasePicksUpWhereTheBarsAre() {
        var motion = iPhone()
        motion.place(70)
        for _ in 0..<3 { motion.settle(toward: 99, dt: 1.0 / 60) }
        let midway = motion.hidden
        XCTAssertTrue((70..<99).contains(midway))
        motion.scroll(by: -10)
        XCTAssertEqual(motion.hidden, midway - 10, accuracy: 0.0001, "No jump when the finger takes over")
    }

    func testNewBarSizesKeepHiddenBarsHidden() {
        var motion = iPhone()
        motion.scroll(by: 200)
        motion.setDistances(navigation: 52, tab: 120)
        XCTAssertTrue(motion.isHidden)
        XCTAssertEqual(motion.tabOffset, 120)
        motion.place(30)
        motion.setDistances(navigation: 44, tab: 99)
        XCTAssertEqual(motion.hidden, 30, "Part-way stays where it is")
        motion.setDistances(navigation: 44, tab: 0)
        XCTAssertEqual(motion.fullDistance, 44, "No tab bar: the navigation bar sets the distance")
    }

    func testTheTraceReadsAsNumbers() {
        var trace = ScrollChromeTrace()
        trace.frames = 12
        trace.fastestEase = 1500.4
        trace.restsHidden = 2
        XCTAssertEqual(trace.summary, "frames=12 faster=0 ease=1500 notBack=0 hidden=2 shown=0 state=0.0 offset=0.0 taps=1 bars=0 same=1 hit=1 seen=0 touches=0 tab=-1")
    }
}
