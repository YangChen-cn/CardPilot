import Foundation
import Testing
@testable import CardPilot

struct CardDeckInteractionTests {
    @Test(arguments: [2, 3, 5, 10])
    func bothDirectionsRevealTheActualDestinationAndWrap(count: Int) {
        let keys = (0..<count).map(String.init)
        for step in [-1, 1] {
            var deck = CardDeckInteraction(keys: keys)
            for _ in 0..<(count * 2) {
                let expected = keys[(deck.selectedIndex + step + count) % count]
                deck.updateDrag(x: CGFloat(-step * 100), y: 2, width: 360)
                #expect(deck.targetKey == expected)
                #expect(deck.depth(of: expected) < 1)
                #expect(deck.visibleKeys.contains(expected))
                let result1 = deck.release(projectedX: CGFloat(-step * 200), width: 360)
                #expect(result1)
                let generation = deck.generation
                deck.finishMotion(width: 360)
                #expect(deck.depth(of: expected) == 0)
                // Every card, not just the target, retains its depth at handoff.
                let depths = Dictionary(uniqueKeysWithValues: keys.map { ($0, deck.depth(of: $0)) })
                let result2 = deck.complete(generation: generation)
                #expect(result2)
                #expect(deck.selectedKey == expected)
                #expect(keys.allSatisfy { deck.depth(of: $0) == depths[$0] })
                #expect(deck.canSelect)
            }
        }
    }

    @Test func directionCanReverseWithoutLosingTheLockedHorizontalAxis() {
        var deck = CardDeckInteraction(keys: ["a", "b", "c", "d", "e"])
        deck.updateDrag(x: -20, y: 2, width: 360)
        #expect(deck.targetKey == "b")
        deck.updateDrag(x: -25, y: 100, width: 360)
        #expect(deck.offset == -25)
        #expect(deck.axis == .horizontal)
        deck.updateDrag(x: 0, y: 100, width: 360)
        #expect(deck.lift == 0)
        deck.updateDrag(x: 100, y: 110, width: 360)
        #expect(deck.targetKey == "e")
        let result3 = deck.release(projectedX: 140, width: 360)
        #expect(result3)
        let result4 = deck.complete(generation: deck.generation)
        #expect(result4)
        #expect(deck.selectedKey == "e")
    }

    @Test func verticalScrollingDoesNotBecomeACardSwipe() {
        var deck = CardDeckInteraction(keys: ["a", "b", "c"])
        deck.updateDrag(x: 2, y: 20, width: 360)
        deck.updateDrag(x: 150, y: 80, width: 360)
        #expect(deck.axis == .vertical)
        #expect(deck.targetKey == nil)
        #expect(deck.offset == 0)
        let result5 = deck.release(projectedX: 500, width: 360)
        #expect(!result5)
        #expect(deck.selectedKey == "a")
        #expect(deck.canSelect)
    }

    @Test func shortDragReturnsAndFastFlickCommitsOnlyInTheRevealedDirection() {
        var deck = CardDeckInteraction(keys: ["a", "b", "c"])
        deck.updateDrag(x: -30, y: 2, width: 360)
        let result6 = deck.release(projectedX: 200, width: 360)
        #expect(!result6)
        deck.finishMotion(width: 360)
        #expect(deck.lift == 0)
        let result7 = deck.complete(generation: deck.generation)
        #expect(!result7)
        #expect(deck.selectedKey == "a")
        deck.updateDrag(x: -20, y: 2, width: 360)
        let result8 = deck.release(projectedX: -200, width: 360)
        #expect(result8)
        let result9 = deck.complete(generation: deck.generation)
        #expect(result9)
        #expect(deck.selectedKey == "b")
    }

    @Test func buttonsAndSwipesCanAlternateImmediatelyAfterCompletion() {
        var deck = CardDeckInteraction(keys: ["a", "b", "c", "d", "e"])
        let result10 = deck.select("e", direction: -1)
        #expect(result10)
        let oldGeneration = deck.generation
        let result11 = deck.select("b", direction: 1)
        #expect(!result11)
        deck.finishMotion(width: 360)
        let result12 = deck.complete(generation: oldGeneration)
        #expect(result12)
        deck.updateDrag(x: -100, y: 0, width: 360)
        let result13 = deck.release(projectedX: -200, width: 360)
        #expect(result13)
        // An earlier completion callback cannot cancel or complete this swipe.
        let result14 = deck.complete(generation: oldGeneration)
        #expect(!result14)
        #expect(deck.phase == .settling)
        let result15 = deck.complete(generation: deck.generation)
        #expect(result15)
        #expect(deck.selectedKey == "a")
        let result16 = deck.select("c", direction: 1) // Tapping a rear edge can skip a card.
        #expect(result16)
        deck.finishMotion(width: 360)
        let depths = deck.keys.map { deck.depth(of: $0) }
        let result17 = deck.complete(generation: deck.generation)
        #expect(result17)
        #expect(deck.keys.map { deck.depth(of: $0) } == depths)
    }

    @Test func cancellationAndFilteringInvalidateCallbacksAndReleaseTheLock() {
        var deck = CardDeckInteraction(keys: ["a", "b", "c"])
        deck.updateDrag(x: -100, y: 0, width: 360)
        deck.returnToRest() // A system-interrupted touch never commits a selection.
        let cancelled = deck.generation
        deck.cancel() // View disappears while returning.
        let result18 = deck.complete(generation: cancelled)
        #expect(!result18)
        #expect(deck.canSelect)
        #expect(deck.selectedKey == "a")
        let result19 = deck.select("b", direction: 1)
        #expect(result19)
        let stale = deck.generation
        deck.reconcile(keys: ["c"])
        let result20 = deck.complete(generation: stale)
        #expect(!result20)
        #expect(deck.selectedKey == "c")
        #expect(deck.canSelect)
        deck.reconcile(keys: [])
        #expect(deck.selectedKey == nil)
        #expect(deck.visibleKeys.isEmpty)
    }

    @Test func reducingMotionCanCompleteTheSameGestureWithoutVisualMotion() {
        var deck = CardDeckInteraction(keys: ["a", "b"])
        deck.updateDrag(x: 100, y: 0, width: 360)
        #expect(deck.restingDepth(of: "b") == 1)
        let result21 = deck.release(projectedX: 200, width: 360)
        #expect(result21)
        // Reduce Motion uses the same recognition but skips finishMotion/animation.
        let result22 = deck.complete(generation: deck.generation)
        #expect(result22)
        #expect(deck.selectedKey == "b")
        #expect(deck.offset == 0)
        #expect(deck.lift == 0)
        #expect(deck.canSelect)
    }

    @Test func rapidSwipeAndButtonInputsQueueInOrderWithoutCancellingTheHandoff() {
        var deck = CardDeckInteraction(keys: ["a", "b", "c", "d", "e"])
        _ = deck.select("b", direction: 1)
        let first = deck.generation
        deck.updateDrag(x: 100, y: 2, width: 360)
        deck.release(projectedX: 200, width: 360) // Reverse swipe while still animating.
        deck.enqueue(step: 1) // Then a Next button tap.
        #expect(deck.phase == .settling)
        #expect(deck.generation == first)
        deck.finishMotion(width: 360)
        deck.complete(generation: first)
        #expect(deck.selectedKey == "b")
        let result101 = deck.nextStep()
        #expect(result101 == -1)
        _ = deck.select("a", direction: -1)
        deck.complete(generation: deck.generation)
        let result102 = deck.nextStep()
        #expect(result102 == 1)
        _ = deck.select("b", direction: 1)
        deck.complete(generation: deck.generation)
        #expect(deck.selectedKey == "b")
        let result103 = deck.nextStep()
        #expect(result103 == nil)
    }

    @Test func touchHeldThroughCompletionRetainsItsAxisAndCanContinueTracking() {
        var deck = CardDeckInteraction(keys: ["a", "b", "c"])
        _ = deck.select("b", direction: 1)
        deck.updateDrag(x: -20, y: 2, width: 360)
        deck.complete(generation: deck.generation)
        #expect(deck.axis == .horizontal)
        deck.updateDrag(x: -100, y: 150, width: 360)
        #expect(deck.targetKey == "c")
        #expect(deck.offset == -100)
        deck.release(projectedX: -200, width: 360)
        deck.complete(generation: deck.generation)
        #expect(deck.selectedKey == "c")
        #expect(deck.canSelect)
    }

    @Test(arguments: [0, 1])
    func emptyAndSingleCardDecksDoNotSwitchOrLeavePendingActions(count: Int) {
        var deck = CardDeckInteraction(keys: (0..<count).map(String.init))
        deck.updateDrag(x: 200, y: 2, width: 360)
        deck.release(projectedX: 400, width: 360)
        #expect(deck.canSelect)
        #expect(deck.targetKey == nil)
        let result104 = deck.nextStep()
        #expect(result104 == nil)
    }
}
