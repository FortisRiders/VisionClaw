import Foundation

struct AppError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }

    static func == (lhs: AppError, rhs: AppError) -> Bool { lhs.message == rhs.message }
}
