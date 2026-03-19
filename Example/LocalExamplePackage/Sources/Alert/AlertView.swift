import SwiftUI

public struct AlertView: View {
    @State private var isAlertPresented: Bool
    @State private var toggleOn: Bool
    
    public init(
        isAlertPresented: Bool = false,
        toggleOn: Bool = false
    ) {
        self._isAlertPresented = State(initialValue: isAlertPresented)
        self._toggleOn = State(initialValue: toggleOn)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Alert View")
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
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Example Content")
                    .font(.title3.weight(.semibold))
                
                Text("Use the button below to present an alert.")
                    .foregroundStyle(.secondary)
            }
            
            
            Toggle(isOn: self.$toggleOn) {
                Text("Toggle: \(self.toggleOn ? "off" : "on")")
            }
            .foregroundStyle(.secondary)
            
            Button {
                self.isAlertPresented = true
            } label: {
                Label("Open Alert", systemImage: "rectangle.portrait.on.rectangle.portrait")
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
        .alert("Ready to snapshot?", isPresented: self.$isAlertPresented) {
            Button("OH NO!", role: .destructive) {}
            Button("Hell yeah!") {}
        } message: {
            Text("There are only bad choices!")
        }
    }
}

#Preview {
    AlertView()
}
