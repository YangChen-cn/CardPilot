import Foundation

/// Ephemeral presentation state only; the user's saved card order is untouched.
struct CardDeckInteraction {
    enum Axis { case horizontal, vertical }
    enum Phase { case idle, dragging, settling, returning }

    private(set) var keys: [String]
    private(set) var selectedKey: String?
    private(set) var targetKey: String?
    private(set) var direction = 1
    private(set) var axis: Axis?
    private(set) var phase = Phase.idle
    private(set) var offset: CGFloat = 0
    private(set) var lift: CGFloat = 0
    private(set) var generation = 0
    private var waitingSteps: [Int] = []
    private var deferredDragX: CGFloat = 0

    init(keys: [String]) {
        self.keys = keys
        selectedKey = keys.first
    }

    var selectedIndex: Int { keys.firstIndex(of: selectedKey ?? "") ?? 0 }
    var canSelect: Bool { phase == .idle && axis == nil }

    /// The target is always directly below the outgoing card, in either direction.
    /// Other rear cards rise by just one layer, never moving sideways.
    func depth(of key: String) -> CGFloat {
        CGFloat(distance(of: key, from: targetKey ?? selectedKey)) + (targetKey == nil ? 0 : 1 - lift)
    }

    func restingDepth(of key: String) -> CGFloat {
        CGFloat(distance(of: key, from: selectedKey))
    }

    private func distance(of key: String, from anchor: String?) -> Int {
        guard let start = keys.firstIndex(of: anchor ?? ""),
              let index = keys.firstIndex(of: key), !keys.isEmpty else { return 0 }
        return (direction * (index - start) + keys.count) % keys.count
    }

    var visibleKeys: [String] {
        keys.filter { $0 == selectedKey || depth(of: $0) < 4 }
    }

    var renderedKeys: [String] {
        guard keys.count > 1 else { return keys }
        // Retain both neighbours, including the normally hidden previous card,
        // so reversing direction does not recreate its async artwork view.
        let neighbours = [keys[(selectedIndex + 1) % keys.count],
                          keys[(selectedIndex - 1 + keys.count) % keys.count]]
        let visible = Set(visibleKeys)
        return keys.filter { visible.contains($0) || neighbours.contains($0) }
    }

    mutating func updateDrag(x: CGFloat, y: CGFloat, width: CGFloat) {
        // Decide once per touch. Diagonal movement cannot switch back to vertical.
        if axis == nil { axis = abs(x) > abs(y) ? .horizontal : .vertical }
        deferredDragX = x
        guard phase == .idle || phase == .dragging else { return }
        guard axis == .horizontal, keys.count > 1 else { return }
        phase = .dragging
        if x != 0 { direction = x < 0 ? 1 : -1 }
        targetKey = keys[(selectedIndex + direction + keys.count) % keys.count]
        offset = x
        lift = min(abs(x) / max(width, 1), 1)
    }

    /// Returns whether this release will select another card. A predicted flick
    /// counts only when it agrees with the card currently being revealed.
    @discardableResult
    mutating func release(projectedX: CGFloat, width: CGFloat) -> Bool {
        guard phase == .dragging else {
            if axis == .horizontal, shouldCommit(x: deferredDragX, projectedX: projectedX, width: width) {
                enqueue(step: deferredDragX < 0 ? 1 : -1)
            }
            endTouch()
            return false
        }
        let commit = shouldCommit(x: offset, projectedX: projectedX, width: width)
        phase = commit ? .settling : .returning
        generation &+= 1
        endTouch()
        return commit
    }

    private func shouldCommit(x: CGFloat, projectedX: CGFloat, width: CGFloat) -> Bool {
        let threshold = max(56, width * 0.18)
        return abs(x) > threshold || (x * projectedX > 0 && abs(projectedX) > threshold * 2)
    }

    mutating func select(_ key: String, direction: Int) -> Bool {
        guard canSelect, keys.contains(key), key != selectedKey else { return false }
        self.direction = direction < 0 ? -1 : 1
        targetKey = key
        phase = .settling
        generation &+= 1
        return true
    }

    mutating func finishMotion(width: CGFloat) {
        if phase == .settling {
            offset = -CGFloat(direction) * (max(width, 1) + 40)
            lift = 1
        } else if phase == .returning {
            offset = 0
            lift = 0
        }
    }

    mutating func returnToRest() {
        guard phase == .dragging else { cancel(); return }
        phase = .returning
        generation &+= 1
        endTouch()
    }

    mutating func enqueue(step: Int) {
        guard keys.count > 1, phase != .idle else { return }
        waitingSteps.append(step < 0 ? -1 : 1)
    }

    mutating func nextStep() -> Int? {
        guard canSelect, !waitingSteps.isEmpty else { return nil }
        return waitingSteps.removeFirst()
    }

    mutating func endTouch() {
        axis = nil
        deferredDragX = 0
    }

    /// A cancelled animation must never complete a newer selection.
    @discardableResult
    mutating func complete(generation: Int) -> Bool {
        guard generation == self.generation, phase == .settling || phase == .returning else { return false }
        let changed = phase == .settling && targetKey != nil
        if changed { selectedKey = targetKey }
        // A new touch may already be in progress while this animation finishes.
        // Preserve its axis and queued actions; only cancel() discards them.
        self.generation &+= 1
        targetKey = nil
        phase = .idle
        offset = 0
        lift = 0
        return changed
    }

    mutating func cancel() {
        generation &+= 1
        targetKey = nil
        axis = nil
        phase = .idle
        offset = 0
        lift = 0
        waitingSteps = []
        deferredDragX = 0
    }

    mutating func reconcile(keys: [String]) {
        cancel()
        self.keys = keys
        if !keys.contains(selectedKey ?? "") { selectedKey = keys.first }
    }
}
