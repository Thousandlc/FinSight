import Testing
import YoushuFoundation

@Suite("Deterministic SHA-256 known vectors")
struct DeterministicSHA256Tests {
    @Test("empty input matches published SHA-256 vector")
    func emptyInputVector() {
        #expect(
            DeterministicSHA256.digestHex("")
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    @Test("abc input matches published SHA-256 vector")
    func abcInputVector() {
        #expect(
            DeterministicSHA256.digestHex("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
