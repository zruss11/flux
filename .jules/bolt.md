## 2026-02-11 - [Recompiling Regexes]
**Learning:** Initializing `NSRegularExpression` inside a frequently called function (like `FillerWordCleaner.clean`) causes unnecessary recompilation on every call, which is expensive.
**Action:** Always pre-compile regexes into static constants when the pattern is constant.

## 2026-02-12 - [Dictionary Replacement Strategy]
**Learning:** Iterating through a dictionary and recompiling regexes for each entry is inefficient (O(N) regex compilations per call).
**Action:** Use a single compiled regex with sorted alternations (`(alias1|alias2|...)`) to perform all replacements in one pass, caching the result based on the dictionary state.

## 2026-02-12 - [Sidecar String Allocations]
**Learning:** Re-allocating large static strings and arrays inside high-frequency functions (like `buildFluxSystemPrompt` and `summarizeToolInput`) in the Node.js sidecar adds unnecessary GC pressure and CPU overhead.
**Action:** Extract static data structures (arrays, large strings) into top-level constants.
