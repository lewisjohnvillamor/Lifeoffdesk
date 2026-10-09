import LifeOffDeskCore
import SwiftUI

/// SF Symbol for a place: from what OSM says it is (police, pickleball, mall…), else its category.
enum PlaceIcon {
    static func symbol(_ place: Place) -> String {
        if place.isFrontier { return "map.fill" }
        if let kind = place.sourceKind, let symbol = byKind[kind] { return symbol }
        return symbol(place.category)
    }

    static func symbol(_ category: PlaceCategory) -> String {
        switch category {
        case .park: return "leaf.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .food: return "fork.knife"
        case .museum: return "building.columns.fill"
        case .library: return "books.vertical.fill"
        case .scenic: return "binoculars.fill"
        case .sports: return "figure.run"
        case .shopping: return "bag.fill"
        case .landmark: return "building.fill"
        case .other: return "mappin"
        }
    }

    static func symbol(_ kind: HelpKind) -> String {
        switch kind {
        case .police: return "shield.lefthalf.filled"
        case .hospital: return "cross.case.fill"
        case .fireStation: return "flame.fill"
        }
    }

    /// Help places stand out in red; everything else uses the brand green.
    static func tint(_ place: Place) -> Color {
        HelpKind(sourceKind: place.sourceKind) != nil ? Theme.danger : Theme.primary
    }

    private static let byKind: [String: String] = [
        "police": "shield.lefthalf.filled", "hospital": "cross.case.fill", "fire_station": "flame.fill",
        "clinic": "stethoscope", "doctors": "stethoscope", "pharmacy": "pills.fill", "chemist": "pills.fill",
        "dentist": "stethoscope",
        "cafe": "cup.and.saucer.fill", "restaurant": "fork.knife", "fast_food": "takeoutbag.and.cup.and.straw.fill",
        "food_court": "fork.knife", "bar": "wineglass.fill", "pub": "mug.fill", "ice_cream": "birthday.cake.fill",
        "bakery": "birthday.cake.fill", "pastry": "birthday.cake.fill",
        "park": "leaf.fill", "garden": "leaf.fill", "playground": "figure.and.child.holdinghands",
        "dog_park": "pawprint.fill", "nature_reserve": "tree.fill",
        "library": "books.vertical.fill", "museum": "building.columns.fill", "gallery": "photo.artframe",
        "arts_centre": "theatermasks.fill", "viewpoint": "binoculars.fill", "cinema": "film.fill",
        "theatre": "theatermasks.fill",
        "tennis": "figure.tennis", "pickleball": "figure.tennis", "badminton": "figure.badminton",
        "basketball": "basketball.fill", "volleyball": "volleyball.fill", "soccer": "soccerball",
        "swimming": "figure.pool.swim", "swimming_pool": "figure.pool.swim", "golf": "figure.golf",
        "golf_course": "figure.golf", "fitness": "dumbbell.fill", "fitness_centre": "dumbbell.fill",
        "fitness_station": "dumbbell.fill", "running": "figure.run", "track": "figure.run",
        "skateboard": "figure.skateboarding", "bowling_alley": "figure.bowling",
        "mall": "bag.fill", "department_store": "bag.fill", "supermarket": "cart.fill", "convenience": "cart.fill",
        "marketplace": "basket.fill", "books": "book.fill", "clothes": "tshirt.fill",
        "place_of_worship": "building.fill", "townhall": "building.columns.fill", "monument": "building.columns.fill",
        "memorial": "building.columns.fill", "attraction": "star.fill", "artwork": "paintpalette.fill",
        "fountain": "drop.fill",
        "bank": "banknote.fill", "school": "graduationcap.fill", "university": "graduationcap.fill",
        "hotel": "bed.double.fill", "spa": "sparkles", "massage": "sparkles", "hairdresser": "scissors",
        "beauty": "sparkles",
    ]
}
