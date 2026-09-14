// Checks an archive's EdDSA signature the way an installed copy does: against `SUPublicEDKey`
// alone, with no private key and no Sparkle.
//
//   swift scripts/release/verify_signature.swift <SUPublicEDKey> <sparkle:edSignature> <archive>

import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: verify_signature.swift <public key> <signature> <archive>\n".utf8))
    exit(2)
}
guard let key = Data(base64Encoded: arguments[1]), key.count == 32 else {
    FileHandle.standardError.write(Data("error: the public key is not 32 bytes of base64\n".utf8))
    exit(2)
}
guard let signature = Data(base64Encoded: arguments[2]) else {
    FileHandle.standardError.write(Data("error: the signature is not base64\n".utf8))
    exit(2)
}
guard let archive = FileManager.default.contents(atPath: arguments[3]) else {
    FileHandle.standardError.write(Data("error: cannot read \(arguments[3])\n".utf8))
    exit(2)
}

let valid = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    .isValidSignature(signature, for: archive)
print(valid ? "EdDSA signature valid" : "EdDSA signature INVALID")
exit(valid ? 0 : 1)
