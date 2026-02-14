import Foundation
import os

// MARK: - ParakeetTokenizer

/// Lightweight SentencePiece-compatible tokenizer for decoding Parakeet model output tokens.
///
/// Parakeet uses SentencePiece with a `▁` (U+2581, LOWER ONE EIGHTH BLOCK) character
/// to represent word boundaries. This tokenizer converts sequences of token IDs back
/// into readable text with proper spacing.
struct ParakeetTokenizer: Sendable {

    /// The vocabulary mapping token IDs to their string representations.
    let vocabulary: [Int: String]

    /// Special token IDs.
    let blankTokenId: Int
    let padTokenId: Int

    /// The SentencePiece word boundary marker.
    private static let wordBoundary: Character = "▁"

    // MARK: - Init

    /// Initialize from a vocabulary dictionary.
    ///
    /// - Parameters:
    ///   - vocabulary: Mapping from token ID to token string.
    ///   - blankTokenId: The blank/CTC token ID (default: 0).
    ///   - padTokenId: The padding token ID (default: -1, meaning unused).
    init(vocabulary: [Int: String], blankTokenId: Int = 0, padTokenId: Int = -1) {
        self.vocabulary = vocabulary
        self.blankTokenId = blankTokenId
        self.padTokenId = padTokenId
    }

    // MARK: - Decoding

    /// Decode a sequence of token IDs into text.
    ///
    /// Handles SentencePiece conventions:
    /// - `▁` at the start of a token indicates a word boundary (space).
    /// - Blank and pad tokens are skipped.
    /// - Consecutive duplicate tokens are collapsed (CTC-style deduplication).
    ///
    /// - Parameter tokenIds: Sequence of integer token IDs from the model output.
    /// - Returns: The decoded text string.
    func decode(_ tokenIds: [Int]) -> String {
        guard !tokenIds.isEmpty else { return "" }

        var pieces: [String] = []
        var previousTokenId: Int?

        for tokenId in tokenIds {
            // Skip blank and pad tokens.
            if tokenId == blankTokenId || tokenId == padTokenId {
                previousTokenId = tokenId
                continue
            }

            // CTC-style deduplication: skip consecutive duplicate tokens.
            if tokenId == previousTokenId {
                continue
            }

            previousTokenId = tokenId

            guard let tokenString = vocabulary[tokenId] else {
                Log.voice.warning("[ParakeetTokenizer] Unknown token ID: \(tokenId)")
                continue
            }

            pieces.append(tokenString)
        }

        return assemblePieces(pieces)
    }

    /// Decode a sequence of token IDs without CTC deduplication.
    ///
    /// Use this for RNNT/TDT output where tokens are already deduplicated by the decoder.
    ///
    /// - Parameter tokenIds: Sequence of integer token IDs from the decoder.
    /// - Returns: The decoded text string.
    func decodeRNNT(_ tokenIds: [Int]) -> String {
        guard !tokenIds.isEmpty else { return "" }

        var pieces: [String] = []

        for tokenId in tokenIds {
            // Skip blank and pad tokens.
            if tokenId == blankTokenId || tokenId == padTokenId {
                continue
            }

            guard let tokenString = vocabulary[tokenId] else {
                Log.voice.warning("[ParakeetTokenizer] Unknown token ID: \(tokenId)")
                continue
            }

            pieces.append(tokenString)
        }

        return assemblePieces(pieces)
    }

    // MARK: - Private

    /// Assemble SentencePiece token strings into readable text.
    private func assemblePieces(_ pieces: [String]) -> String {
        guard !pieces.isEmpty else { return "" }

        var result = ""

        for piece in pieces {
            if piece.hasPrefix(String(Self.wordBoundary)) {
                // Word boundary: add a space before the rest of the token.
                let content = String(piece.dropFirst())
                if !result.isEmpty {
                    result += " "
                }
                result += content
            } else {
                // Continuation piece: append directly (no space).
                result += piece
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
