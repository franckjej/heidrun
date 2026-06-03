import SwiftUI

extension View {
  public func adaptiveSheet<Content: View>(isPresent: Binding<Bool>, @ViewBuilder sheetContent: () -> Content) -> some View {
    modifier(AdaptiveSheetModifier(isPresented: isPresent, sheetContent))
  }
}

struct AdaptiveSheetModifier<SheetContent: View>: ViewModifier {
  @Binding var isPresented: Bool
  @State private var subHeight: CGFloat = 0
  var sheetContent: SheetContent

  init(isPresented: Binding<Bool>, @ViewBuilder _ content: () -> SheetContent) {
    _isPresented = isPresented
    sheetContent = content()
  }

  func body(content: Content) -> some View {
    content
      .background(
        sheetContent
          .background(
            GeometryReader { proxy in
              Color.clear
                .task(id: proxy.size.height) {
                  subHeight = proxy.size.height
                }
            }
          )
          .hidden()
      )
      .sheet(isPresented: $isPresented) {
        sheetContent
          .presentationDetents([.height(subHeight)])
      }
      .id(subHeight)
  }
}

struct ContentView: View {
  @State var show = false
  @State var height: CGFloat = 250
  var body: some View {
    List {
      Button("Pop Sheet") {
        height = 250
        show.toggle()
      }
      Button("Pop ScrollView Sheet") {
        height = 1000
        show.toggle()
      }
    }
    .adaptiveSheet(isPresent: $show) {
      ViewThatFits(in: .vertical) {
        SheetView(height: height)
        ScrollView {
          SheetView(height: height)
        }
      }
    }
  }
}

struct SheetView: View {
  let height: CGFloat
  var body: some View {
    Text("Hi")
      .frame(maxWidth: .infinity, minHeight: height)
      .presentationBackground(.orange)
  }
}
