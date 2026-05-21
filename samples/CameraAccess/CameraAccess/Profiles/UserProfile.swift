import Foundation

struct UserProfile: Codable, Identifiable, Equatable {
  let id: UUID
  var firstName: String
  var lastName: String
  var email: String
  let createdAt: Date

  var fullName: String { "\(firstName) \(lastName)" }

  var initials: String {
    let f = firstName.first.map(String.init) ?? ""
    let l = lastName.first.map(String.init) ?? ""
    return (f + l).uppercased()
  }

  var shortId: String { String(id.uuidString.prefix(8)).lowercased() }
}
