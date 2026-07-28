import Foundation
import Security

extension ControllerIdentity {
  public init(leafCertificateIn trust: SecTrust) throws {
    guard
      let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
      let leaf = chain.first
    else {
      throw ControllerIdentityError.missingLeafCertificate
    }
    try self.init(certificateDER: SecCertificateCopyData(leaf) as Data)
  }
}
