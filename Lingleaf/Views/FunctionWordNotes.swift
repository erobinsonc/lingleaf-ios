import SwiftUI
import LingleafCore

// What the word card says about a helper or modal verb (SPEC S16).

extension FunctionWord.Kind {
    /// Nil for a contraction: the card's headword ("it is") already says what it is.
    var label: String? {
        switch self {
        case .helper: String(localized: "Helper verb")
        case .modal: String(localized: "Modal verb")
        case .contraction: nil
        }
    }
}

extension FunctionWord {
    /// One short line on what the word does here. `form` is the word as tapped ("did", "didn't").
    func note(form: String) -> String {
        // "I'll" keeps its capital I; other words are shown in lower case.
        let word = form.hasPrefix("I'") || form.hasPrefix("I’") ? form : form.lowercased()
        if let expansion { return contractionNote(word, expansion) }
        let contracted = TextTools.normalize(word).hasSuffix("n't")
        let negative = contracted ? word : "\(word) not"
        let expanded = Self.expanded[TextTools.normalize(word)] ?? negative
        // A perfect's helper as tapped, with "not" when it follows: "has not" for "has not seen".
        let shown = self.negative && !contracted ? "\(word) not" : word
        switch use {
        case .pastNegative where contracted:
            return String(localized: "“\(negative)” (= “\(expanded)”) + base verb = past negative: “didn't go”, not “didn't went”.")
        case .pastNegative:
            return String(localized: "“\(negative)” + base verb = past negative: “did not go”, not “did not went”.")
        case .presentNegative where contracted:
            return String(localized: "“\(negative)” (= “\(expanded)”) + base verb = present negative: “\(negative) like”, not “\(negative) likes”.")
        case .presentNegative:
            return String(localized: "“\(negative)” + base verb = present negative: “\(negative) like”, not “\(negative) likes”.")
        case .prohibition:
            return String(localized: "“\(negative)” + base verb tells someone not to do it: “Don't touch”.")
        case .questionTag:
            return String(localized: "“\(word)” + pronoun at the end asks the listener to agree, like “right?”.")
        case .pastQuestion:
            return String(localized: "“\(word)” starts a question about the past.")
        case .presentQuestion:
            return String(localized: "“\(word)” starts a question about the present.")
        case .modal(let base) where self.negative:
            // The meaning can flip: "must" = necessary, "mustn't" = not allowed.
            let shown = contracted || word == "cannot" ? word : "\(word) not"
            if base == "must" { return String(localized: "“\(shown)” + verb: it is not allowed.") }
            if contracted || word == "cannot" {
                // One argument for "can not", so the key matches the translated one.
                let full = "\(base) not"
                return String(localized: "“\(shown)” (= “\(full)”): the negative of “\(base)” + verb.")
            }
            return String(localized: "“\(shown)”: the negative of “\(base)” + verb.")
        case .modal(let base):
            return Self.modalNote(base)
        case .presentPerfect:
            return String(localized: "“\(shown)” + past participle: it happened before now and still matters: “seen”, not “saw”.")
        case .pastPerfect:
            return String(localized: "“\(shown)” + past participle: it happened before another past moment: “had left”.")
        case .hadBetter:
            return String(localized: "“had better” + verb: strong advice: “You'd better go”.")
        case .contraction:
            return String(localized: "“\(word)” = “\(base)”.")
        }
    }

    /// A pronoun contraction: what it stands for, and what it does when it is a helper here.
    private func contractionNote(_ word: String, _ expansion: String) -> String {
        switch use {
        case .presentPerfect:
            return String(localized: "“\(word)” (= “\(expansion)”) + past participle: it happened before now and still matters: “seen”, not “saw”.")
        case .pastPerfect:
            return String(localized: "“\(word)” (= “\(expansion)”) + past participle: it happened before another past moment: “had left”.")
        case .hadBetter:
            return String(localized: "“'d better” (= “had better”) + verb: strong advice: “You'd better go”.")
        case .modal("will"):
            return String(localized: "“\(word)” (= “\(expansion)”) + verb: the future.")
        case .modal:
            return String(localized: "“\(word)” (= “\(expansion)”) + verb: an imagined result, or a polite request.")
        default:
            let key = TextTools.normalize(word)
            // "he'd put": had or would; the sentence's translation settles it.
            let both = expansion.components(separatedBy: " / ")
            if both.count == 2 {
                return String(localized: "“\(word)” can be “\(both[0])” or “\(both[1])”: the sentence's translation tells which.")
            }
            if key == "let's" { return String(localized: "“let's” (= “let us”) + verb: a suggestion to do something together: “Let's go”.") }
            // The lookalikes learners mix up.
            if key == "it's" { return String(localized: "“it's” = “\(expansion)”; “its” (no apostrophe) = belonging to it.") }
            if key == "who's" { return String(localized: "“who's” = “\(expansion)”; “whose” = of whom: “Whose book?”") }
            return String(localized: "“\(word)” = “\(expansion)”.")
        }
    }

    private static let expanded = ["didn't": "did not", "don't": "do not", "doesn't": "does not"]

    private static func modalNote(_ base: String) -> String {
        switch base {
        case "will": String(localized: "“will” + verb: the future.")
        case "would": String(localized: "“would” + verb: what would happen, or a polite request.")
        case "can": String(localized: "“can” + verb: be able to, or be allowed to.")
        case "could": String(localized: "“could” + verb: was able to, or it’s possible.")
        case "shall": String(localized: "“shall” + verb: the future, or an offer (“Shall we go?”).")
        case "should": String(localized: "“should” + verb: advice, what is right to do.")
        case "must": String(localized: "“must” + verb: it is necessary, or it is surely true.")
        case "may": String(localized: "“may” + verb: maybe, or permission.")
        default: String(localized: "“might” + verb: maybe.")
        }
    }
}
