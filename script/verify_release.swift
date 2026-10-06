import Foundation

import CryptoKit

func require(_ condition: Bool, _ message: String) {
    if !condition { fputs("Release verification failed: \(message)\n", stderr); exit(1) }
}
require(CommandLine.arguments.count == 4, "usage: verify_release.swift Info.plist appcast-v2.xml release.dmg")
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), format: nil) as! [String: Any]
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
let feed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let marker = Data("<!-- sparkle-signatures:".utf8)
guard let range = feed.range(of: marker, options: .backwards) else { fatalError("Missing feed signature") }
let signedData = feed.prefix(range.lowerBound)
let trailer = String(decoding: feed[range.lowerBound...], as: UTF8.self)
let regex = try NSRegularExpression(pattern: "^<!-- sparkle-signatures:\\s*edSignature: ([A-Za-z0-9+/=]+)\\s*length: ([0-9]+)\\s*-->\\s*$")
guard let match = regex.firstMatch(in: trailer, range: NSRange(trailer.startIndex..., in: trailer)),
      let signatureRange = Range(match.range(at: 1), in: trailer),
      let lengthRange = Range(match.range(at: 2), in: trailer),
      let signature = Data(base64Encoded: String(trailer[signatureRange])) else { fatalError("Invalid feed signature trailer") }
require(Int(trailer[lengthRange]) == signedData.count, "signed feed length")
require(publicKey.isValidSignature(signature, for: signedData), "feed signature")

final class FeedParser: NSObject, XMLParserDelegate {
    var enclosures = [[String: String]]()
    var build = ""
    var version = ""
    var item = 0
    var element = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        element = name
        if name == "item" { item += 1 }
        if name == "enclosure", item == 1 { enclosures.append(attributes) }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) {
        if item == 1 && element == "sparkle:version" { build += text }
        if item == 1 && element == "sparkle:shortVersionString" { version += text }
    }
    func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) { element = "" }
}
let delegate = FeedParser()
let parser = XMLParser(data: signedData)
parser.delegate = delegate
require(parser.parse(), "feed XML")
require(delegate.build.trimmingCharacters(in: .whitespacesAndNewlines) == info["CFBundleVersion"] as? String, "feed build does not match app")
require(delegate.version.trimmingCharacters(in: .whitespacesAndNewlines) == info["CFBundleShortVersionString"] as? String, "feed version does not match app")
let archiveURL = URL(fileURLWithPath: CommandLine.arguments[3])
let archive = try Data(contentsOf: archiveURL)
guard let enclosure = delegate.enclosures.first,
      let signatureText = enclosure["sparkle:edSignature"],
      let archiveSignature = Data(base64Encoded: signatureText),
      let downloadURL = URL(string: enclosure["url"] ?? "") else { fatalError("Missing signed enclosure") }
require(downloadURL.scheme == "https", "release URL must use HTTPS")
require(downloadURL.lastPathComponent == archiveURL.lastPathComponent, "archive filename mismatch")
require(Int(enclosure["length"] ?? "") == archive.count, "archive length")
require(publicKey.isValidSignature(archiveSignature, for: archive), "archive signature")
print("Verified feed and DMG signatures, version, build, and archive length using only the embedded public key.")
