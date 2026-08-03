import SwiftUI

struct ActionButtonLabel: View {
  let title: Text
  let systemImage: String
  var isBusy = false

  var body: some View {
    HStack(spacing: 10) {
      if isBusy {
        ProgressView()
          .controlSize(.small)
      } else {
        Image(systemName: systemImage)
      }

      title
    }
    .font(.body.weight(.semibold))
    .frame(maxWidth: .infinity, minHeight: 44)
    .contentShape(Rectangle())
  }
}
