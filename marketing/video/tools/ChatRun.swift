import Foundation
import LifeOffDeskCore

let root = URL(fileURLWithPath: "/home/user/Lifeoffdesk/LifeOffDesk/Resources/StarterData")
SafetyKeywords.lexicon = try SafetyLexicon.decode(Data(contentsOf: root.appendingPathComponent("safety-lexicon.json")))
let guide = try SafetyGuide.decode(Data(contentsOf: root.appendingPathComponent("safety-guide.json")))
let hotlines = try HotlineDirectory.decode(Data(contentsOf: root.appendingPathComponent("hotlines.json")))
let catalog = try PlaceCatalog.decode(Data(contentsOf: root.appendingPathComponent("makati-cbd-starter/places.json")))
var out: [[String: Any]] = []

// Same pipeline as SafetyChat.ask with no model answer (keyword layer): what the app shows offline.
for q in ["nag-overheat ang makina, pwede bang buhusan ng tubig?",
          "may nahimatay, hindi humihinga si lola",
          "May metal sheet na nakasugat sa akin",
          "stroke"] {
    let final = SafetyPrompt.combine(model: nil, question: q)
    let card = final.topic.flatMap { guide.card($0) }
    let hl = card.flatMap { SafetyKeywords.lexicon?.relevantSteps(in: $0, for: q) } ?? []
    let local = final.emergency ? hotlines.forEmergency(regionID: "makati-cbd-starter") : []
    out.append(["q": q, "topic": final.topic?.rawValue ?? "none", "emergency": final.emergency, "title": card?.title ?? "",
                "steps": card?.steps ?? [], "highlights": hl, "source": card?.sourceTitle ?? "",
                "hotlines": local.map { ["name": $0.name, "numbers": $0.numbers] }])
}
for q in ["Ano ang number ng NLEX?", "number ng highway patrol"] {
    out.append(["q": q, "asking": hotlines.isAsking(q),
                "hotlines": hotlines.answer(for: q, regionID: "makati-cbd-starter").map { ["name": $0.name, "numbers": $0.numbers, "source": $0.sourceName] }])
}
// Lost flow at a fixed demo position (Ayala Ave near Paseo de Roxas, Makati; labelled demo in the video).
let here = Coordinate(latitude: 14.5568, longitude: 121.0236)
let loc = HelpPlaces.locationDescription(here, accuracyMeters: 8, catalog: catalog)
let found = PlaceNameSearch.find("Greenbelt", in: catalog, from: here)
out.append(["lost": loc, "search": "Greenbelt", "places": found.map { ["name": $0.name, "m": Int(Geo.distanceMeters(here, $0.coordinate))] }])
let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)
