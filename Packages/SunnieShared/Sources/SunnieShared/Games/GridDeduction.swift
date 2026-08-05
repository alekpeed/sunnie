import Foundation

/// A filled grid: for every category, which value sits at every position.
///
/// `assignment[category][position] == valueIndex`.
public struct GridSolution: Hashable, Sendable {
    public let assignment: [[Int]]

    public init(assignment: [[Int]]) {
        self.assignment = assignment
    }

    /// The position holding a value, or nil if the category or value is out of
    /// range.
    public func position(ofValue value: Int, inCategory category: Int) -> Int? {
        guard assignment.indices.contains(category) else { return nil }
        return assignment[category].firstIndex(of: value)
    }
}

/// Solves and grades the deduction puzzle behind Jungle Logic
/// (GAMES_AND_FUTURE_MULTIPLAYER.md §3, G-03).
///
/// The spec requires a unique solution, which is a property of the *clues*, not
/// of the code that reads them. So the solver's real job is not to solve the
/// puzzle for the player — it is to prove, at content-validation time, that
/// exactly one arrangement satisfies every clue. A puzzle with two solutions or
/// none is a content bug that fails the tests before it can reach a player and
/// tell them their correct answer is wrong.
public enum GridDeductionSolver {

    /// What a search found.
    public enum Outcome: Hashable, Sendable {
        case unique(GridSolution)
        case none
        case multiple
        /// The search hit its work limit. Reported rather than guessed at,
        /// because "we did not finish looking" is not the same claim as "there is
        /// more than one answer".
        case indeterminate
    }

    /// Ceiling on permutations examined.
    ///
    /// Authored puzzles are four or five positions across a handful of
    /// categories, which is thousands of nodes. This limit is two orders of
    /// magnitude above that: high enough never to stop a real puzzle, low enough
    /// that a malformed pack cannot hang a test run or a device.
    public static let searchLimit = 2_000_000

    /// Finds up to two solutions, which is all that is needed to answer
    /// "is it unique?".
    public static func solve(_ puzzle: GridPuzzle) -> Outcome {
        guard puzzle.isWellFormed else { return .none }

        let positions = puzzle.positionCount
        let categoryCount = puzzle.categories.count
        let permutations = Self.permutations(of: positions)

        var found: [GridSolution] = []
        var budget = searchLimit
        var exhausted = false

        /// `assignment[category][position] = value`
        var assignment = [[Int]](
            repeating: [Int](repeating: 0, count: positions), count: categoryCount
        )

        func search(_ category: Int) {
            if exhausted || found.count >= 2 { return }

            if category == categoryCount {
                found.append(GridSolution(assignment: assignment))
                return
            }

            for permutation in permutations {
                if exhausted || found.count >= 2 { return }
                budget -= 1
                if budget <= 0 {
                    exhausted = true
                    return
                }

                // `permutation[position] = valueIndex`.
                assignment[category] = permutation

                if satisfiesConstraints(
                    puzzle, assignment: assignment, assignedThrough: category
                ) {
                    search(category + 1)
                }
            }
        }

        search(0)

        if exhausted { return .indeterminate }
        switch found.count {
        case 0: return .none
        case 1: return .unique(found[0])
        default: return .multiple
        }
    }

    /// Checks every constraint whose categories are all assigned so far.
    ///
    /// Partial checking is what keeps the search tractable: a clue relating
    /// categories 0 and 1 rejects a bad first pair before the remaining
    /// categories are ever enumerated.
    static func satisfiesConstraints(
        _ puzzle: GridPuzzle,
        assignment: [[Int]],
        assignedThrough category: Int
    ) -> Bool {
        for constraint in puzzle.constraints {
            switch constraint {
            case .same(let catA, let valA, let catB, let valB):
                guard catA <= category, catB <= category else { continue }
                guard
                    let posA = position(assignment, catA, valA),
                    let posB = position(assignment, catB, valB)
                else { return false }
                if posA != posB { return false }

            case .different(let catA, let valA, let catB, let valB):
                guard catA <= category, catB <= category else { continue }
                guard
                    let posA = position(assignment, catA, valA),
                    let posB = position(assignment, catB, valB)
                else { return false }
                if posA == posB { return false }

            case .atPosition(let cat, let value, let expected):
                guard cat <= category else { continue }
                guard let actual = position(assignment, cat, value) else { return false }
                if actual != expected { return false }

            case .adjacent(let catA, let valA, let catB, let valB):
                guard catA <= category, catB <= category else { continue }
                guard
                    let posA = position(assignment, catA, valA),
                    let posB = position(assignment, catB, valB)
                else { return false }
                if abs(posA - posB) != 1 { return false }

            case .before(let catA, let valA, let catB, let valB):
                guard catA <= category, catB <= category else { continue }
                guard
                    let posA = position(assignment, catA, valA),
                    let posB = position(assignment, catB, valB)
                else { return false }
                if posA >= posB { return false }
            }
        }
        return true
    }

    private static func position(
        _ assignment: [[Int]], _ category: Int, _ value: Int
    ) -> Int? {
        guard assignment.indices.contains(category) else { return nil }
        return assignment[category].firstIndex(of: value)
    }

    /// All orderings of `0..<count`.
    ///
    /// Generated once per solve and reused for every category, because the set of
    /// permutations does not depend on which category is being placed.
    static func permutations(of count: Int) -> [[Int]] {
        guard count > 0 else { return [[]] }

        var result: [[Int]] = []
        var current = Array(0..<count)

        func recurse(_ index: Int) {
            if index == count {
                result.append(current)
                return
            }
            for swapIndex in index..<count {
                current.swapAt(index, swapIndex)
                recurse(index + 1)
                current.swapAt(index, swapIndex)
            }
        }
        recurse(0)
        return result
    }
}
