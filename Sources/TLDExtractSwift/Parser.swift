//
//  Created by Kojiro futamura on 2018/11/16.
//

import Foundation
import Punycode

class PSLParser {
    var exceptions: [PSLData] = .init()
    var wildcards: [PSLData] = .init()
    var normals: Set<String> = .init()

    func addLine(_ line: String) {
        if line.contains("*") {
            self.wildcards.append(PSLData(raw: line))
        } else if line.starts(with: "!") {
            self.exceptions.append(PSLData(raw: line))
        } else {
            self.normals.insert(line)
        }
    }

    func parse(data: Data?, useFrozenData: Bool = false) throws -> PSLDataSet {
        guard let data: Data = data, let str = String(data: data, encoding: .utf8), str.count > 0 else {
            throw TLDExtractError.pslParseError(message: nil)
        }

        for line in str.components(separatedBy: .newlines) {
            if useFrozenData {
                guard !line.isEmpty else {
                    continue
                }
            } else {
                guard !line.starts(with: "//"),
                      !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
            }

            self.addLine(line)

            if !useFrozenData {
                if let encoded = line.idnaEncoded,
                   encoded != line {
                    self.addLine(encoded)
                }
            }
        }

        return PSLDataSet(
            exceptions: self.exceptions,
            wildcards: self.wildcards,
            normals: self.normals
        )
    }
}

class TLDParser {
    private let pslDataSet: PSLDataSet

    init(dataSet: PSLDataSet) {
        self.pslDataSet = dataSet
    }

    func parseExceptionsAndWildcards(host: String) -> TLDResult? {
        let hostComponents: [String] = host.lowercased().components(separatedBy: ".")
        /// Search exceptions first, then search wildcards if not match
        let matchClosure: (PSLData) -> Bool = { $0.matches(hostComponents: hostComponents) }
        let pslData: PSLData? = self.pslDataSet.exceptions.first(where: matchClosure) ?? self.pslDataSet.wildcards.first(where: matchClosure)
        return pslData?.parse(hostComponents: hostComponents)
    }

    func parseNormals(host: String) -> TLDResult? {
        let tldSet: Set<String> = self.pslDataSet.normals
        /// Split the hostname to components
        let hostComponents = host.lowercased().components(separatedBy: ".")
        /// A host must have at least two parts else it's a TLD
        guard hostComponents.count >= 2 else { return nil }
        /// Iterate from lower level domain and check if the hostname matches a suffix in the dataset
        var copiedHostComponents: ArraySlice<String> = ArraySlice(hostComponents)
        var topLevelDomain: String?
        repeat {
            guard !copiedHostComponents.isEmpty else { return nil }
            topLevelDomain = copiedHostComponents.joined(separator: ".")
            copiedHostComponents = copiedHostComponents.dropFirst()
        } while !tldSet.contains(topLevelDomain ?? "")

        if topLevelDomain == host {
            topLevelDomain = nil
        }

        /// Extract the host name to each level domain
        let rootDomainRange: Range<Int> = (copiedHostComponents.startIndex - 2)..<hostComponents.endIndex
        let rootDomain: String? = rootDomainRange.startIndex >= 0 ? hostComponents[rootDomainRange].joined(separator: ".") : nil

        let secondDomainRange: Range<Int> = (rootDomainRange.lowerBound)..<(rootDomainRange.lowerBound + 1)
        let secondDomain: String? = secondDomainRange.startIndex >= 0 ? hostComponents[secondDomainRange].joined(separator: ".") : nil

        let subDomainRange: Range<Int> = (hostComponents.startIndex)..<max(secondDomainRange.lowerBound, hostComponents.startIndex)
        let subDomain: String? = subDomainRange.endIndex >= 1 ? hostComponents[subDomainRange].joined(separator: ".") : nil

        return TLDResult(
            rootDomain: rootDomain,
            topLevelDomain: topLevelDomain,
            secondLevelDomain: secondDomain,
            subDomain: subDomain
        )
    }
}
