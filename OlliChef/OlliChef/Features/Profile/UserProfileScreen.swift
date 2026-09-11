import SwiftUI

/// Placeholder — account settings, sign-out, and delete-account land in the Profile phase.
struct UserProfileScreen: View {
    var body: some View {
        Text("Profile")
            .font(AppTypography.headline)
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.surfaceBody)
    }
}
