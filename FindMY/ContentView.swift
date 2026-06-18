import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var locationManager = LocationManager()

    // PERSISTENCE: Saves location permanently even if app closes
    @AppStorage("parkedLat") private var storedLat: Double = 0.0
    @AppStorage("parkedLon") private var storedLon: Double = 0.0
    @AppStorage("parkedTimestamp") private var storedTimestamp: Double = 0.0
    
    // Computed property to get the coordinate easily
    var lastParkedCoordinate: CLLocationCoordinate2D? {
        if storedLat == 0.0 && storedLon == 0.0 { return nil }
        return CLLocationCoordinate2D(latitude: storedLat, longitude: storedLon)
    }
    
    var lastParkedDate: Date? {
        if storedTimestamp == 0.0 { return nil }
        return Date(timeIntervalSince1970: storedTimestamp)
    }

    @State private var wasConnected = false
    @State private var showDeviceInfo = false

    var body: some View {
        ZStack {
            GlassBackgroundView(isDisconnected: !bleManager.isConnected && !bleManager.isScanning)

            VStack(spacing: 0) {
                // 1. APP NAME - Simple text without background
                Text("FUBLE")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.top, 16)
                
                Spacer()

                // 2. PROXIMITY LOGIC
                let state = proximityState(
                    for: bleManager.rssiValue,
                    isConnected: bleManager.isConnected,
                    isScanning: bleManager.isScanning
                )

                // 3. RADAR / HALO
                ProximityHaloView(
                    strength: state.strength,
                    isActive: bleManager.isConnected,
                    isSearching: bleManager.isScanning && !bleManager.isConnected,
                    isVeryClose: state.level == .veryClose
                )
                .frame(height: 320)

                // 4. TEXT LABELS
                VStack(spacing: 8) {
                    Text(state.label)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)

                    Text(state.sublabel)
                        .font(.subheadline)
                        .foregroundColor(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 4)
                
                Spacer()

                // 5. COMBINED DEVICE CARD
                CombinedDeviceCard(
                    isConnected: bleManager.isConnected,
                    isScanning: bleManager.isScanning,
                    onTapSignal: {
                        if bleManager.isConnected || bleManager.isScanning {
                            bleManager.disconnect()
                        } else {
                            bleManager.reconnect()
                        }
                    },
                    onTapInfo: {
                        showDeviceInfo = true
                    }
                )

                // 6. PARKED LOCATION BUTTON
                if let coord = lastParkedCoordinate {
                    ParkedLocationButton(
                        coordinate: coord,
                        timestamp: lastParkedDate
                    ) {
                        openMaps(coordinate: coord)
                    }
                    .padding(.top, 12)
                }
                
                // Bottom margin
                Spacer()
                    .frame(height: 32)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showDeviceInfo) {
            DeviceInfoSheet(
                deviceId: bleManager.deviceInfo?.deviceId,
                strength: proximityState(
                    for: bleManager.rssiValue,
                    isConnected: bleManager.isConnected,
                    isScanning: bleManager.isScanning
                ).strength,
                isConnected: bleManager.isConnected
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            print("🔵 ContentView appeared")
            locationManager.requestAuthorization()
            locationManager.start()
            
            // Debug: Check location status after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if let loc = locationManager.lastLocation {
                    print("📍 Location available after 2s: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
                } else {
                    print("⚠️ Still no location after 2 seconds")
                }
            }
        }
        .onChange(of: bleManager.isConnected) { newValue in
            print("🔵 Connection changed: wasConnected=\(wasConnected), newValue=\(newValue)")
            
            // Detect transition from connected -> disconnected
            if wasConnected && newValue == false {
                print("🔵 Detected disconnect, checking location...")
                if let loc = locationManager.lastLocation {
                    storedLat = loc.coordinate.latitude
                    storedLon = loc.coordinate.longitude
                    storedTimestamp = Date().timeIntervalSince1970
                    print("✅ Saved parked location: \(storedLat), \(storedLon) at \(Date())")
                } else {
                    print("❌ No location available to save")
                }
            }
            wasConnected = newValue
        }
    }
    
    private func openMaps(coordinate: CLLocationCoordinate2D) {
        let urlString = "http://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(kDeviceName)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - COMBINED DEVICE CARD
struct CombinedDeviceCard: View {
    let isConnected: Bool
    let isScanning: Bool
    let onTapSignal: () -> Void
    let onTapInfo: () -> Void
    
    private var iconName: String {
        if isConnected { return "antenna.radiowaves.left.and.right" }
        if isScanning { return "dot.radiowaves.left.and.right" }
        return "antenna.radiowaves.left.and.right.slash"
    }

    private var iconColor: Color {
        if isConnected { return .mint }
        if isScanning { return .cyan }
        return Color.white.opacity(0.6)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left: Scooter name + info icon
            HStack(spacing: 8) {
                Text(kDeviceName)
                    .font(.subheadline.weight(.semibold))  // or .callout
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Button(action: onTapInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Spacer()
            
            // Center: Connection badge
            Text(isConnected ? "Connected" : (isScanning ? "Scanning…" : "Disconnected"))
                .font(.caption.weight(.medium))
                .foregroundColor(isConnected ? Color.green : (isScanning ? Color.cyan : Color.gray))
                .padding(.horizontal,12)
                .padding(.vertical, 4)
                .background(
                    (isConnected ? Color.green : (isScanning ? Color.cyan : Color.gray))
                        .opacity(0.18)
                )
                .clipShape(Capsule())

            // Right: Signal icon button
            Button(action: onTapSignal) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .shadow(color: .black.opacity(0.8), radius: 8, x: 0, y: 0)

                    Image(systemName: iconName)
                        .font(.system(size: 22))
                        .foregroundColor(iconColor)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Color.black.opacity(0.6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - OTHER SUBVIEWS (Unchanged)

struct GlassBackgroundView: View {
    let isDisconnected: Bool
    
    var body: some View {
        ZStack {
            RadialGradient(
                colors: isDisconnected ? [
                    Color(red: 0.15, green: 0.15, blue: 0.15),
                    Color(red: 0.05, green: 0.05, blue: 0.05)
                ] : [
                    Color(red: 0.02, green: 0.04, blue: 0.10),
                    Color.black
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()

            Circle()
                .fill(isDisconnected ? Color.gray.opacity(0.2) : Color.green.opacity(0.3))
                .blur(radius: 120)
                .frame(width: 260, height: 260)
                .offset(x: -120, y: 180)

            Circle()
                .fill(isDisconnected ? Color.gray.opacity(0.15) : Color.blue.opacity(0.25))
                .blur(radius: 140)
                .frame(width: 280, height: 280)
                .offset(x: 130, y: -180)
        }
        .animation(.easeInOut(duration: 0.5), value: isDisconnected)
    }
}

struct ProximityHaloView: View {
    let strength: Double
    let isActive: Bool
    let isSearching: Bool
    let isVeryClose: Bool
    
    @State private var rippleScale1: CGFloat = 0.4
    @State private var rippleOpacity1: Double = 0.4
    @State private var rippleScale2: CGFloat = 0.4
    @State private var rippleOpacity2: Double = 0.4
    @State private var pulseScale: CGFloat = 1.0

    private var ringColor: Color {
        isActive ? .mint : Color.white.opacity(0.25)
    }

    private var dotColor: Color {
        isActive ? Color.green : Color.gray.opacity(0.7)
    }

    private var dotOffset: CGFloat {
        guard isActive else { return 0 }
        let maxDistance: CGFloat = 130
        let inverted = 1.0 - strength
        return maxDistance * CGFloat(inverted)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                // Ripple rings when searching
                if isSearching {
                    Circle()
                        .stroke(Color.cyan.opacity(rippleOpacity1), lineWidth: 2)
                        .frame(width: size * rippleScale1, height: size * rippleScale1)
                    
                    Circle()
                        .stroke(Color.cyan.opacity(rippleOpacity2), lineWidth: 2)
                        .frame(width: size * rippleScale2, height: size * rippleScale2)
                }
                
                // Static rings - hide when searching
                if !isSearching {
                    Circle()
                        .stroke(ringColor.opacity(0.3), lineWidth: 2)
                        .frame(width: size * 0.9, height: size * 0.9)

                    Circle()
                        .stroke(ringColor.opacity(0.5), lineWidth: 1.5)
                        .frame(width: size * 0.65, height: size * 0.65)

                    Circle()
                        .stroke(ringColor.opacity(0.7), lineWidth: 1)
                        .frame(width: size * 0.4, height: size * 0.4)
                }
                
                // User position dot (moves based on proximity)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [dotColor, dotColor.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: dotColor.opacity(1.0), radius: 20)
                    .offset(y: -dotOffset)
                    .animation(isActive ? .easeOut(duration: 0.25) : .none,
                               value: strength)
                
                // Scooter image at center (stationary - represents the scooter)
                // Rendered LAST so it's on top of all circles
                Image(isVeryClose ? "Scooter_Found" : "Scooter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: isVeryClose ? 56 : 40, height: isVeryClose ? 56 : 40)
                    .scaleEffect(pulseScale)
                    .opacity(isActive ? 1.0 : (isSearching ? 0.8 : 0.5))
                    .grayscale(isActive ? 0.0 : (isSearching ? 0.3 : 1.0))
                    .shadow(
                        color: isVeryClose ? Color.green.opacity(0.9) : (isActive ? Color.mint.opacity(0.6) : (isSearching ? Color.cyan.opacity(0.4) : Color.gray.opacity(0.3))),
                        radius: isVeryClose ? 32 : 24
                    )
                    .animation(.easeInOut(duration: 0.3), value: isVeryClose)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isActive ? 1.0 : (isSearching ? 0.8 : 0.4))
            .grayscale(isActive ? 0.0 : (isSearching ? 0.3 : 0.9))
            .onAppear {
                if isSearching {
                    startRippleAnimation()
                }
                if isVeryClose {
                    startPulseAnimation()
                }
            }
            .onChange(of: isSearching) { newValue in
                if newValue {
                    startRippleAnimation()
                } else {
                    stopRippleAnimation()
                }
            }
            .onChange(of: isVeryClose) { newValue in
                if newValue {
                    startPulseAnimation()
                } else {
                    stopPulseAnimation()
                }
            }
        }
    }
    
    private func startRippleAnimation() {
        // First ripple
        withAnimation(Animation.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
            rippleScale1 = 1.0
            rippleOpacity1 = 0.0
        }
        
        // Second ripple (delayed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(Animation.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                rippleScale2 = 1.0
                rippleOpacity2 = 0.0
            }
        }
    }
    
    private func stopRippleAnimation() {
        rippleScale1 = 0.4
        rippleOpacity1 = 0.4
        rippleScale2 = 0.4
        rippleOpacity2 = 0.4
    }
    
    private func startPulseAnimation() {
        withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
    }
    
    private func stopPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.3)) {
            pulseScale = 1.0
        }
    }
}

// MARK: - DEVICE INFO SHEET
struct DeviceInfoSheet: View {
    let deviceId: String?
    let strength: Double
    let isConnected: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Text("Device Information")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                
                Text(kDeviceName)
                    .font(.body.weight(.regular))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 12)
            
            // Device ID
            VStack(alignment: .leading, spacing: 8) {
                Text("Device ID")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(deviceId ?? "Unknown")
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            
            // Signal Strength
            VStack(alignment: .leading, spacing: 12) {
                Text("Signal Strength")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.mint)
                        .frame(width: max(UIScreen.main.bounds.width - 48, 0) * CGFloat(strength), height: 8)
                        .animation(.easeOut(duration: 0.25), value: strength)
                }
                
                HStack {
                    Text("\(Int(strength * 100))%")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(isConnected ? "Updated just now" : "Not connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
}

struct ParkedLocationButton: View {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date?
    let onOpenMaps: () -> Void
    
    private var timeAgoText: String {
        guard let timestamp = timestamp else { return "" }
        
        let interval = Date().timeIntervalSince(timestamp)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)
        
        if minutes < 1 {
            return "Just now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else {
            return "\(days)d ago"
        }
    }

    var body: some View {
        Button(action: onOpenMaps) {
            HStack(spacing: 12) {
                // Icon Container
                ZStack {
                    Circle()
                        .fill(Color.mint.opacity(0.2))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "map.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.mint)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parked")
                        .font(.headline.weight(.medium))
                        .foregroundColor(.white)
                    
                    if timestamp != nil {
                        Text(timeAgoText)
                            .font(.caption)
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            // Added the dark backing to match your preference for "Top Card" style
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}
