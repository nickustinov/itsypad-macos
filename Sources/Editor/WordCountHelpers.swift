import Foundation

enum WordCountHelpers {
    static func wordCount(in text: String) -> Int {
        var count = 0
        var isInWord = false

        for scalar in text.unicodeScalars {
            let isWordChar = scalar.value == 95 || CharacterSet.alphanumerics.contains(scalar)

            if isWordChar {
                if !isInWord {
                    count += 1
                }
                isInWord = true
            } else {
                isInWord = false
            }
        }

        return count
    }
}
