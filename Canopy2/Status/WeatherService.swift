import AppKit
import CoreLocation

struct WeatherNow: Equatable {
    var temperature: Double
    var high: Double?
    var low: Double?
    var code: Int
    var isDay: Bool
    var place: String

    var rounded: String { "\(Int(temperature.rounded()))°" }

    /// SF Symbol for a WMO weather code (as used by Open-Meteo).
    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }
    var title: String { self == .celsius ? "Celsius (°C)" : "Fahrenheit (°F)" }

    static var localDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

/// Current weather from Open-Meteo (free, no key). Location: a city typed in
/// Settings, or else the Mac's approximate location (Location Services).
@MainActor
final class WeatherService: NSObject, ObservableObject {
    @Published private(set) var current: WeatherNow?
    @Published private(set) var status = "Off"

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var isEnabled = false
    private var generation = 0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Applies the current settings (on/off, unit, city) and refreshes.
    func configure() {
        isEnabled = Prefs.bool(Prefs.weatherEnabled)
        timer?.invalidate()
        timer = nil
        guard isEnabled else {
            current = nil
            status = "Off"
            return
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    func refresh() {
        guard isEnabled else { return }
        generation += 1
        let city = Prefs.string(Prefs.weatherCity).trimmingCharacters(in: .whitespacesAndNewlines)
        if !city.isEmpty {
            status = "Looking up \(city)…"
            let expected = generation
            Task {
                guard let place = await OpenMeteo.geocode(city) else {
                    if expected == generation { status = "Couldn't find \"\(city)\"" }
                    return
                }
                await load(latitude: place.latitude, longitude: place.longitude, place: place.name, generation: expected)
            }
            return
        }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            status = "Waiting for location permission…"
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = "Location is off: type a city in Settings"
        default:
            status = "Finding your location…"
            locationManager.requestLocation()
        }
    }

    private func load(latitude: Double, longitude: Double, place: String, generation expected: Int) async {
        let unit = TemperatureUnit(rawValue: Prefs.string(Prefs.weatherUnit)) ?? .localDefault
        guard let weather = await OpenMeteo.current(latitude: latitude, longitude: longitude, unit: unit, place: place),
              expected == generation else {
            if expected == generation { status = "Couldn't load the weather" }
            return
        }
        current = weather
        status = place.isEmpty ? "Updated" : "Updated for \(place)"
    }

    private func located(latitude: Double, longitude: Double, place: String) {
        let expected = generation
        Task { await load(latitude: latitude, longitude: longitude, place: place, generation: expected) }
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let place = placemarks?.first?.locality ?? ""
            Task { @MainActor in self.located(latitude: latitude, longitude: longitude, place: place) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.current == nil { self.status = "Couldn't get your location: type a city in Settings" }
        }
    }
}

enum OpenMeteo {
    struct Place: Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    static func geocode(_ city: String) async -> Place? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url,
              let json = await fetchJSON(url),
              let first = (json["results"] as? [[String: Any]])?.first,
              let latitude = (first["latitude"] as? NSNumber)?.doubleValue,
              let longitude = (first["longitude"] as? NSNumber)?.doubleValue else { return nil }
        return Place(name: first["name"] as? String ?? city, latitude: latitude, longitude: longitude)
    }

    static func current(latitude: Double, longitude: Double, unit: TemperatureUnit, place: String) async -> WeatherNow? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
        ]
        guard let url = components?.url,
              let json = await fetchJSON(url),
              let current = json["current"] as? [String: Any],
              let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue else { return nil }
        let daily = json["daily"] as? [String: Any]
        return WeatherNow(
            temperature: temperature,
            high: (daily?["temperature_2m_max"] as? [NSNumber])?.first?.doubleValue,
            low: (daily?["temperature_2m_min"] as? [NSNumber])?.first?.doubleValue,
            code: (current["weather_code"] as? NSNumber)?.intValue ?? 3,
            isDay: (current["is_day"] as? NSNumber)?.intValue != 0,
            place: place
        )
    }

    private static func fetchJSON(_ url: URL) async -> [String: Any]? {
        guard let response = try? await URLSession.shared.data(from: url),
              (response.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: response.0)) as? [String: Any]
    }
}
