/// Fails if any element of `items` appears twice, naming the first
/// duplicate's positions.
///
/// ```swift
/// try assertUnique(ids) // expected unique elements, but 7 appears at index 2 and 5
/// ```
public func assertUnique<S: Sequence>(_ items: S) throws where S.Element: Hashable {
  NativeBridge.preload()
  var firstIndex: [S.Element: Int] = [:]
  for (index, item) in items.enumerated() {
    if let first = firstIndex[item] {
      throw SuggestedTestsFailure(
        "expected unique elements, but \(item) appears at index \(first) and \(index)")
    }
    firstIndex[item] = index
  }
}
