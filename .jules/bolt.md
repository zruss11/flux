## 2026-02-11 - [Recompiling Regexes]
**Learning:** Initializing `NSRegularExpression` inside a frequently called function (like `FillerWordCleaner.clean`) causes unnecessary recompilation on every call, which is expensive.
**Action:** Always pre-compile regexes into static constants when the pattern is constant.

## 2026-02-12 - [Dictionary Replacement Strategy]
**Learning:** Iterating through a dictionary and recompiling regexes for each entry is inefficient (O(N) regex compilations per call).
**Action:** Use a single compiled regex with sorted alternations (`(alias1|alias2|...)`) to perform all replacements in one pass, caching the result based on the dictionary state.

## 2026-02-12 - [Sidecar String Allocations]
**Learning:** Re-allocating large static strings and arrays inside high-frequency functions (like `buildFluxSystemPrompt` and `summarizeToolInput`) in the Node.js sidecar adds unnecessary GC pressure and CPU overhead.
**Action:** Extract static data structures (arrays, large strings) into top-level constants.

## 2026-02-15 - [Regex Combination Optimization]
**Learning:** Iterating through an array of `RegExp` objects for matching (O(N*M)) is slower than combining them into a single `RegExp` with alternations (O(N)), especially for frequently executed checks like security validations.
**Action:** Combine multiple regex patterns into a single compiled regex using `|` alternations where possible.

## 2026-02-16 - [Node.js Environment Access & Array Chains]
**Learning:** Accessing `process.env` inside high-frequency functions (like `sanitizeChatImages`) adds overhead. Chained array methods (`.slice().filter().map()`) create unnecessary intermediate arrays.
**Action:** Extract environment variables to top-level constants. Replace array method chains with single-pass loops where performance matters.
## 2026-02-27 - [Image Parsing Optimization]
**Learning:** In the Node.js sidecar, when parsing large strings (e.g., base64 images), avoid `trim()` and full-string regex captures (`match`) as they cause expensive allocations. Use manual index-based scanning (`charCodeAt`, `indexOf`, `startsWith`) instead. When needing the byte length of a base64 string for logging or previews, calculate it mathematically `(length * 3) / 4 - padding` based on string length and padding (`=`) rather than decoding into a Buffer to save memory.
**Action:** When extracting data from large payloads or logging them, calculate properties algorithmically and slice explicitly rather than doing regex captures.
