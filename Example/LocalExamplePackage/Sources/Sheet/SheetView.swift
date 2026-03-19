import SwiftUI

public struct SheetView: View {
    @State private var isSheetPresented: Bool
    @State private var toggleOn: Bool
    
    public init(
        isSheetPresented: Bool = false,
        toggleOn: Bool = false
    ) {
        self._isSheetPresented = State(initialValue: isSheetPresented)
        self._toggleOn = State(initialValue: toggleOn)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sheet View")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                
                Text("I'm a view from a local Swift package.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 12) {
                Label("SwiftUI", systemImage: "sparkles")
                Label("SPM", systemImage: "square.stack.3d.up.fill")
                Label("Snapshots", systemImage: "camera.aperture")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.blue)
            
            Toggle(isOn: self.$toggleOn) {
                Text("Toggle: \(self.toggleOn ? "off" : "on")")
            }
            .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Sheet")
                    .font(.title3.weight(.semibold))
                
                Text("Use the button below to present a sheet.")
                    .foregroundStyle(.secondary)
            }
            
            Button {
                self.isSheetPresented = true
            } label: {
                Label("Open Example Sheet", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.98, blue: 1.0),
                    Color(red: 0.90, green: 0.95, blue: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .sheet(isPresented: self.$isSheetPresented) {
            FooSheetView()
        }
    }
}

private struct FooSheetView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Label("Oh wow, a Sheet", systemImage: "rectangle.inset.filled.and.person.filled")
                    .font(.title2.weight(.bold))
                
                Text("Smile while we take a photo of this view 📸")
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("The laws of germany", systemImage: "checkmark.seal")
                    Label("Be nice to mommy", systemImage: "text.justify")
                    Label("Don't talk to commies", systemImage: "rectangle.compress.vertical")
                    Label("Eat kosher salamis", systemImage: "heater.vertical")
                }
                .font(.headline)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .navigationTitle("Foo Details")
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    SheetView()
}
