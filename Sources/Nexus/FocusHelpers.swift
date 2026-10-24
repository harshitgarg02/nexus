import SwiftUI

extension View {
    /// Puts the cursor in a text field when its screen appears. Setting focus inside `onAppear` alone races with
    /// the field being installed (it "works sometimes"), so retry on the next run-loop turn and once more shortly after.
    func refocusOnAppear(_ focus: FocusState<Bool>.Binding) -> some View {
        onAppear {
            focus.wrappedValue = true
            DispatchQueue.main.async { focus.wrappedValue = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { focus.wrappedValue = true }
        }
    }
}
