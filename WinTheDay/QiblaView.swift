import SwiftUI
import CoreLocation

@MainActor
final class QiblaManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var heading: Double = 0          // device heading (° from north)
    @Published var qiblaBearing: Double = 0     // bearing to the Kaaba from here
    @Published var headingAvailable = true
    @Published var haveLocation = false

    private let kaaba = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)

    func start() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.headingFilter = 1
            manager.startUpdatingHeading()
        } else {
            headingAvailable = false
        }
    }

    func stop() { manager.stopUpdatingHeading(); manager.stopUpdatingLocation() }

    /// Angle to rotate the Qibla arrow so it points to Makkah relative to where the phone faces.
    var arrowAngle: Double { qiblaBearing - heading }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = h }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let from = loc.coordinate
        let kaaba = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)
        let φ1 = from.latitude * .pi / 180, φ2 = kaaba.latitude * .pi / 180
        let Δλ = (kaaba.longitude - from.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let bearing = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        Task { @MainActor in self.qiblaBearing = bearing; self.haveLocation = true }
    }
}

struct QiblaView: View {
    @StateObject private var qibla = QiblaManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                VStack(spacing: 24) {
                    Text("Point the top of your phone forward and turn until the arrow lines up with Makkah.")
                        .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                        .multilineTextAlignment(.center).padding(.horizontal, 30).padding(.top, 10)

                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
                            .shadow(color: Color(hex: 0x2A3350).opacity(0.12), radius: 14, y: 6)
                        // cardinal ticks rotate opposite to heading
                        compassDial.rotationEffect(.degrees(-qibla.heading))
                        // qibla arrow
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.accentDark], startPoint: .top, endPoint: .bottom))
                            .rotationEffect(.degrees(qibla.arrowAngle))
                            .animation(.easeOut(duration: 0.2), value: qibla.arrowAngle)
                        VStack {
                            Image(systemName: "building.columns.fill").font(.system(size: 16)).foregroundStyle(Theme.accentDark)
                            Spacer()
                        }
                        .frame(height: 220)
                        .rotationEffect(.degrees(qibla.arrowAngle))
                    }
                    .frame(width: 280, height: 280)

                    VStack(spacing: 4) {
                        Text("\(Int(qibla.qiblaBearing))° from North")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        if !qibla.headingAvailable {
                            Text("Compass not available on this device.")
                                .font(.system(size: 13)).foregroundStyle(Color(hex: 0xD86B4A))
                        } else if !qibla.haveLocation {
                            Text("Getting your location…").font(.system(size: 13)).foregroundStyle(Theme.tertiaryInk)
                        }
                    }
                    Spacer()
                }
            }
            .navigationTitle("Qibla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .onAppear { qibla.start() }
            .onDisappear { qibla.stop() }
        }
        .tint(Theme.accentDark)
    }

    private var compassDial: some View {
        ZStack {
            ForEach(["N", "E", "S", "W"].indices, id: \.self) { i in
                VStack {
                    Text(["N", "E", "S", "W"][i])
                        .font(.system(size: 14, weight: i == 0 ? .bold : .regular))
                        .foregroundStyle(i == 0 ? Theme.accentDark : Theme.secondaryInk)
                    Spacer()
                }
                .frame(height: 250)
                .rotationEffect(.degrees(Double(i) * 90))
            }
        }
    }
}
