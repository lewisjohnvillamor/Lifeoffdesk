#!/usr/bin/env python3
"""Writes LifeOffDesk/Resources/StarterData/hotlines.json: emergency and road hotlines for the
offline help chat. Every number comes from the listed page (checked 2026-10-09); "official" means a
government/operator page, "secondary" a news report quoting the operator (shown as such in the app).
Re-check before shipping; numbers change. Edit here, then run it."""
import json
from pathlib import Path

CHECKED = "2026-10-09"
H = []
def add(id, group, name, numbers, aliases, source_name, url, confidence="official"):
    H.append(dict(id=id, group=group, name=name, numbers=numbers, aliases=aliases, sourceName=source_name,
                  sourceURL=url, retrieved=CHECKED, confidence=confidence))

# National (order matters: the first non-911 lines are shown under emergency answers).
add("911", "national", "Emergency 911 (police, fire, ambulance)", ["911"], ["911", "pulis", "police", "ambulansya", "ambulance"],
    "DILG: Unified 911 nationwide", "https://calabarzon.dilg.gov.ph/one-number-for-all-emergencies-unified-911-to-launch-nationwide/")
add("redcross", "national", "Philippine Red Cross", ["143", "(02) 8790 2300"], ["red cross", "redcross", "pula krus"],
    "Philippine Red Cross", "https://redcross.org.ph/")
add("mmda", "national", "MMDA Metrobase (Metro Manila roads)", ["136"], ["mmda", "metrobase", "traffic", "trapik", "edsa"],
    "MMDA", "https://mmda.gov.ph/20-faq/5482-8-things-that-drivers-should-know-updated-june-7-2022.html")
add("hpg", "national", "PNP Highway Patrol Group", ["0917 683 3333", "(02) 723 0401"], ["highway patrol", "hpg", "highway police"],
    "PNP Highway Patrol Group", "https://hpg.pnp.gov.ph/contact-us/")
add("doh", "national", "DOH health hotline", ["1555"], ["doh", "department of health"],
    "Department of Health", "https://doh.gov.ph/contact-us/")
add("coastguard", "national", "Philippine Coast Guard", ["(02) 8527 3877"], ["coast guard", "pcg", "dagat", "nalulunod sa dagat"],
    "Philippine Coast Guard", "https://www.coastguard.gov.ph/index.php/contact-us")

# Expressways.
add("mptc", "expressway", "NLEX, SCTEX, CAVITEX, CALAX (MPTC)", ["1-35000"], ["nlex", "sctex", "cavitex", "calax", "mptc"],
    "MPTC expressways advisory", "https://www.mptc.com.ph/mptc_expressways_on_full_alert_this_semana_santa")
add("slex", "expressway", "SLEX", ["(049) 508 7539", "0917 687 7539"], ["slex", "south luzon expressway"],
    "Philstar, quoting San Miguel tollways (Dec 2024)",
    "https://www.philstar.com/headlines/2024/12/20/2408773/expressway-toll-fees-be-waived-during-holidays", "secondary")
add("skyway", "expressway", "Skyway and NAIAX", ["(02) 5318 8655", "0917 539 8762"], ["skyway", "naiax"],
    "Philstar, quoting San Miguel tollways (Dec 2024)",
    "https://www.philstar.com/headlines/2024/12/20/2408773/expressway-toll-fees-be-waived-during-holidays", "secondary")
add("star", "expressway", "STAR Tollway", ["(043) 756 7870", "0917 511 7827"], ["star tollway", "star expressway"],
    "Philstar, quoting San Miguel tollways (Dec 2024)",
    "https://www.philstar.com/headlines/2024/12/20/2408773/expressway-toll-fees-be-waived-during-holidays", "secondary")
add("tplex", "expressway", "TPLEX", ["0917 888 0715"], ["tplex"],
    "Philstar, quoting San Miguel tollways (Dec 2024)",
    "https://www.philstar.com/headlines/2024/12/20/2408773/expressway-toll-fees-be-waived-during-holidays", "secondary")

# Metro Manila LGU rescue / DRRM lines (Navotas omitted: no current official number found).
lgu = [
 ("makati", "Makati Rescue", ["(02) 8895 8243", "(02) 8899 8928", "(02) 8870 1191"], ["makati"], "Makati city directory", "https://www.makati.gov.ph/assets/static/city-directory.json"),
 ("muntinlupa", "Muntinlupa Emergency (Command Center)", ["137-175", "(02) 8373 5165", "0921 542 7123", "0927 257 9322"], ["muntinlupa", "alabang"], "Muntinlupa City emergency hotlines", "https://muntinlupacity.gov.ph/"),
 ("taguig", "Taguig Command Center / Rescue", ["(02) 8789 3200", "0919 070 3112"], ["taguig", "bgc", "bonifacio global city"], "Taguig City peace and order", "https://www.taguig.gov.ph/peace-and-order/"),
 ("pasay", "Pasay DRRMO C3", ["0917 867 2263", "(02) 7758 5746"], ["pasay"], "Pasay City emergency numbers", "https://www.pasay.gov.ph/"),
 ("paranaque", "Parañaque emergency", ["(02) 8820 7783", "0961 096 6249"], ["paranaque", "parañaque"], "Parañaque City hotlines", "https://paranaque.gov.ph/emergency-disaster-preparedness-hotlines/"),
 ("manila", "Manila MDRRMO", ["(02) 8463 3295", "0950 700 3710"], ["manila", "maynila"], "City of Manila MDRRMO", "https://manila.gov.ph/mdrrmo/"),
 ("quezoncity", "QC Helpline", ["122"], ["quezon city", "qc"], "Quezon City", "https://quezoncity.gov.ph/"),
 ("mandaluyong", "Mandaluyong CDRRMO", ["(02) 8533 2225", "0956 427 3727"], ["mandaluyong"], "Mandaluyong City", "https://mandaluyong.gov.ph/"),
 ("sanjuan", "San Juan CDRRMO", ["137-135"], ["san juan"], "San Juan City", "https://www.sanjuancity.gov.ph/SanJuanCity/Makabagong_SJ_Departments_Selected/45"),
 ("marikina", "Marikina Rescue 161", ["161", "(02) 161"], ["marikina"], "Marikina City", "https://www.marikina.gov.ph/contact-us"),
 ("caloocan", "Caloocan CDRRMO / Rescue", ["(02) 5310 2700", "(02) 5310 7536"], ["caloocan"], "Caloocan City directory", "https://caloocancity.gov.ph/about-us/directory/"),
 ("malabon", "Malabon DRRMO", ["281-4999 loc. 1017"], ["malabon"], "Malabon City emergency hotlines", "https://malabon.gov.ph/emergency-hotlines/"),
 ("valenzuela", "Valenzuela CDRRMO", ["(02) 8292 1405", "(02) 8352 5000"], ["valenzuela"], "Valenzuela City", "https://www.valenzuela.gov.ph/"),
 ("laspinas", "Las Piñas DRRM Office", ["(02) 8871 4343", "(02) 8873 0765"], ["las pinas", "las piñas"], "Las Piñas City directory", "https://laspinascity.gov.ph/directory"),
 ("pateros", "Pateros Rescue", ["(02) 8642 5159"], ["pateros"], "Municipality of Pateros", "https://pateros.gov.ph/"),
]
for id, name, numbers, aliases, source, url in lgu:
    add(id, "lgu", name, numbers, aliases, source, url)

out = {"note": "Offline hotline copy. Source and check date per entry; 'secondary' = news report quoting the operator. Re-check before release.",
       "hotlines": H,
       "regionLGU": {"makati-cbd-starter": "makati", "muntinlupa": "muntinlupa", "taguig": "taguig", "pasay": "pasay", "paranaque": "paranaque"}}
path = Path(__file__).resolve().parents[1] / "LifeOffDesk/Resources/StarterData/hotlines.json"
path.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n")
print(f"{len(H)} hotlines -> {path}")
