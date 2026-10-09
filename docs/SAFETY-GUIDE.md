# Offline help assistant (SOS → Ask the help assistant)

**What it is:** an offline chat in the SOS sheet. You type or say what happened in Taglish or English, and you get a bundled help card.

**How it answers:**
- The on-device model (Qwen3-1.7B) only **routes** the question. It returns grammar-constrained JSON with one of 19 topics (or unknown) and an emergency flag.
- A keyword check on the user's own words can **raise** the emergency flag (never lower it). It also picks a topic when the model is unavailable.
- The answer is always the bundled card in `LifeOffDesk/Resources/StarterData/safety-guide.json`. **The model never writes advice.**
- Emergencies show a **Call 911** button first.
- Unknown questions get "no reviewed guide; call 911 if in danger".

## Sources (fetched 2026-10-09; steps are short paraphrases, nothing added)
- **NHS:** cuts and bleeding, burns, sprains, heat exhaustion and heatstroke, fainting, anaphylaxis, dehydration, insect stings, snake bites (UK page), poisoning (used for wild plants and mushrooms).
- **St John Ambulance:** choking (adult), CPR (adult).
- **WHO:** rabies (dog/cat bites), floods.
- **US National Weather Service:** lightning safety.
- **Apple Support:** Low Power Mode.

UK pages say 999; the app shows **911** (the Philippine emergency hotline).

Mayo Clinic, American Red Cross and the Philippine DOH sites refused automated fetching (HTTP 403), so they are not used. A DOH/Philippine Red Cross review would be a good replacement where it applies, especially for rabies (DOH animal bite treatment centres).

## Life Off Desk app guidance (not medical)
The cards **unsafe**, **lost** and **noGPS** describe only what the app can do: call 911, copy or text your location, route to the nearest police station, and work offline. They are written by the project, not taken from a third-party source.

## Deliberate limits
- **No plant or mushroom identification.** A description is not enough, and a wrong identification can kill. The card says so and gives the poisoning steps.
- **No free-form medical chat.** A 1.7B model can make things up, so it only picks cards.
- **Not reviewed by a clinician.** The founder should review the cards before release.
