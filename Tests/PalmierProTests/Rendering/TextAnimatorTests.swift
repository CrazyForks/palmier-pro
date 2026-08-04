import Testing
@testable import PalmierPro

@Suite("TextAnimator")
struct TextAnimatorTests {
    private let base = TextStyle.RGBA(r: 1, g: 1, b: 1, a: 1)
    private let highlight = TextStyle.RGBA(r: 1, g: 0.8, b: 0, a: 1)
    private let word = WordTiming(text: "ONE", startFrame: 0, endFrame: 10)

    @Test func highlightPopFinishesMotionThenHoldsHighlightUntilNextWord() {
        let animation = TextAnimation(preset: .highlightPop, perWordFrames: 6, highlight: highlight)

        let peak = state(animation, rel: 3)
        let settled = state(animation, rel: 6)
        let gap = state(animation, rel: 20)
        let nextWord = state(animation, rel: 30)

        #expect(peak.scale > 1)
        #expect(settled.scale == 1)
        #expect(settled.color == highlight)
        #expect(gap == settled)
        #expect(nextWord.scale == 1)
        #expect(nextWord.color == base)
    }

    @Test func highlightBlockSwitchesAtNextWordWithoutFading() {
        let animation = TextAnimation(preset: .highlightBlock, perWordFrames: 6, highlight: highlight)

        #expect(state(animation, rel: 0).bgColor == highlight)
        #expect(state(animation, rel: 20).bgColor == highlight)
        #expect(state(animation, rel: 29).bgColor == highlight)
        #expect(state(animation, rel: 30).bgColor == nil)
    }

    @Test func wordCycleUsesFixedEntranceAndHoldsAcrossSpokenWordGap() {
        let animation = TextAnimation(preset: .wordCycle, perWordFrames: 6, highlight: highlight)

        #expect(state(animation, rel: 3).opacity > 0)
        #expect(state(animation, rel: 6).opacity == 1)
        #expect(state(animation, rel: 20).opacity == 1)
        #expect(state(animation, rel: 30).opacity == 0)
    }

    @Test func perWordHighlightHoldsAcrossSpokenWordGap() {
        let animation = TextAnimation(preset: .wordReveal, perWordFrames: 6, highlight: highlight)

        #expect(state(animation, rel: 6).color == highlight)
        #expect(state(animation, rel: 20).color == highlight)
        #expect(state(animation, rel: 30).color == base)
    }

    private func state(_ animation: TextAnimation, rel: Int) -> TextAnimator.WordState {
        TextAnimator.wordState(
            animation,
            word: word,
            activeUntil: 30,
            rel: rel,
            base: base
        )
    }
}
