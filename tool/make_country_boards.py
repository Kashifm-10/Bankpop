"""Builds supabase/boards.sql from tool/data/board_template.json.

Boards live in the database, not in the app, so this script writes the table
and its seed rows. A board is the *names* of the spaces: the prices, rents,
colour groups, building costs and the order of the tiles are the same in every
board, which is what lets the banker pick one at the table without changing a
rule. The template supplies those numbers once; this script only renames the
properties for each country.

Names are real places (a handful are invented streets), never the trademarks of
another board game. Stations keep the word "Station" at the end of the name -
the creation screen enforces the same rule - and the two utilities keep
"Electric" and "City Water", because the tiles draw their own artwork for them.

Chance and Community Chest are rebuilt by rewriting the space names they
mention, so "Advance to ..." points at a space on this board.

Run it after editing a name or adding a country:

    python tool/make_country_boards.py
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "data", "board_template.json")
OUTPUT = os.path.join(HERE, "..", "supabase", "boards.sql")

# id, name, flag, 22 property names in board order, 4 station names.
#
# Property order follows the template: brown 1-2, light blue 3, pink 3,
# orange 3, red 3, yellow 3, green 3, dark blue 2.
COUNTRIES = [
    (
        "india",
        "India",
        "\U0001F1EE\U0001F1F3",
        [
            "Warli Village Road", "Chai Stall Lane",
            "Marine Drive", "Juhu Beach Road", "Bandra Hill Road",
            "Charminar Chowk", "Gateway Promenade", "Lotus Courtyard",
            "Connaught Circle", "Brigade Road", "Chowringhee Row",
            "Marina Beach Road", "Rajpath Avenue", "Fort Kochi Walk",
            "MG Road", "Park Street", "Sector 17 Plaza",
            "Dal Lake Drive", "Tea Garden Terrace", "Backwater Boulevard",
            "Taj Mahal Gardens", "Amber Palace Heights",
        ],
        [
            "Mumbai Terminus Station", "New Delhi Junction Station",
            "Chennai Central Station", "Howrah Station",
        ],
    ),
    (
        "usa",
        "United States",
        "\U0001F1FA\U0001F1F8",
        [
            "Route 66 Lane", "Homestead Road",
            "Sunset Strip", "Lake Shore Drive", "Cotton Row",
            "Liberty Square", "Union Market Way", "Foundry Street",
            "Prairie Avenue", "Cattle Trail Road", "Rail Depot Row",
            "Broadway Plaza", "Capitol Avenue", "Golden Gate Drive",
            "Desert Mesa Road", "Canyon Rim Way", "Skyline Boulevard",
            "Everglade Parkway", "Redwood Terrace", "Lakeside Promenade",
            "Empire Heights", "Presidential Boulevard",
        ],
        [
            "Grand Central Station", "Union Depot Station",
            "Pacific Terminal Station", "Atlantic Junction Station",
        ],
    ),
    (
        "uk",
        "United Kingdom",
        "\U0001F1EC\U0001F1E7",
        [
            "Cobblestone Mews", "Fisherman's Row",
            "Harbour Lane", "Cliffside Walk", "Mill Race Road",
            "Crown Parade", "Abbey Courtyard", "Cathedral Close",
            "Coal Wharf Road", "Trinity Square", "Cutty Sark Way",
            "Soho Square", "Thames Embankment", "Kew Garden Road",
            "Dartmoor Way", "Moorland Drive", "Stone Circle Way",
            "Highland Terrace", "Lakeside Gardens", "Windsor Great Park",
            "Westminster Bridge", "Royal Crescent",
        ],
        [
            "Bristol Temple Station", "York Station",
            "Edinburgh Waverley Station", "Cardiff Central Station",
        ],
    ),
    (
        "france",
        "France",
        "\U0001F1EB\U0001F1F7",
        [
            "Rue du Pain", "Impasse des Fleurs",
            "Quai de Seine", "Rue des Vignes", "Place du Marché",
            "Boulevard des Arts", "Cour du Louvre", "Rue de la Paix",
            "Canal Saint-Martin", "Place Bellecour", "Rue des Écoles",
            "Avenue des Champs", "Pont Neuf", "Place de la Concorde",
            "Champs de Lavande", "Côte d'Azur Drive", "Rue de Rivoli",
            "Jardin Terrace", "Montmartre Heights", "Bordeaux Quay",
            "Château Gardens", "Tour Eiffel Avenue",
        ],
        [
            "Gare du Nord Station", "Gare de Lyon Station",
            "Saint-Lazare Station", "Montparnasse Station",
        ],
    ),
    (
        "germany",
        "Germany",
        "\U0001F1E9\U0001F1EA",
        [
            "Brotgasse", "Altstadtweg",
            "Rheinpromenade", "Lindenstraße", "Marktplatz",
            "Kaiserallee", "Museumsufer", "Glockengasse",
            "Handelsstraße", "Schlossplatz", "Werftstraße",
            "Friedrichsallee", "Königsplatz", "Brückenstraße",
            "Biergartenweg", "Schwarzwaldweg", "Domplatz",
            "Elbterrasse", "Gartenstadtweg", "Burgpromenade",
            "Brandenburg Allee", "Schlossgarten Allee",
        ],
        [
            "Hauptbahnhof Station", "Ostbahnhof Station",
            "Westkreuz Station", "Südbahnhof Station",
        ],
    ),
    (
        "italy",
        "Italy",
        "\U0001F1EE\U0001F1F9",
        [
            "Vicolo del Pane", "Via degli Artisti",
            "Lungomare", "Via dei Fiori", "Piazza del Mercato",
            "Via della Moda", "Corso Umberto", "Piazza Navona",
            "Via dei Fori", "Ponte Vecchio", "Viale dei Mille",
            "Via Veneto", "Piazza del Popolo", "Via Garibaldi",
            "Strada del Vino", "Costiera Drive", "Piazza San Marco",
            "Giardini Terrace", "Colline Toscane", "Canal Grande Walk",
            "Colosseo Avenue", "Duomo Heights",
        ],
        [
            "Termini Station", "Milano Centrale Station",
            "Santa Lucia Station", "Porta Nuova Station",
        ],
    ),
    (
        "spain",
        "Spain",
        "\U0001F1EA\U0001F1F8",
        [
            "Calle del Pan", "Callejón de las Flores",
            "Paseo del Mar", "Calle de los Olivos", "Plaza Mayor",
            "Paseo de Gracia", "Calle Alcalá", "Rambla del Arte",
            "Puerta del Sol", "Calle Mayor", "Barrio de Santa Cruz",
            "Gran Vía", "Plaza de España", "Avenida de Andalucía",
            "Ruta del Sol", "Viñedos Road", "Costa Blanca Drive",
            "Alhambra Gardens", "Sierra Terrace", "Jardines del Retiro",
            "Sagrada Heights", "Palacio Boulevard",
        ],
        [
            "Atocha Station", "Sants Station",
            "Santa Justa Station", "Abando Station",
        ],
    ),
    (
        "japan",
        "Japan",
        "\U0001F1EF\U0001F1F5",
        [
            "Sakura Lane", "Tofu Alley",
            "Uji Tea Road", "Onsen Street", "Momiji Path",
            "Ginza Promenade", "Kiyomizu Slope", "Sumida River Walk",
            "Namba Market Street", "Scramble Crossing Road", "Akihabara Row",
            "Tokyo Tower Road", "Osaka Castle Avenue", "Gion Corner",
            "Fuji View Road", "Bamboo Grove Path", "Hokkaido Drive",
            "Imperial Gardens Walk", "Seto Inland Way", "Ise Shrine Road",
            "Tokyo Skyline Heights", "Golden Pavilion Estate",
        ],
        [
            "Shinjuku Station", "Kyoto Station",
            "Umeda Station", "Nagoya Station",
        ],
    ),
    (
        "china",
        "China",
        "\U0001F1E8\U0001F1F3",
        [
            "Hutong Lane", "Tea House Alley",
            "Riverside Walk", "Willow Street", "Lantern Market",
            "Jade Garden Road", "Silk Road Avenue", "Pagoda Square",
            "Nanjing Road", "Bell Tower Street", "Drum Tower Lane",
            "Pearl River Promenade", "Golden Roof Boulevard",
            "Imperial Canal Walk",
            "Great Wall Road", "Terracotta Way", "Kite Festival Street",
            "West Lake Gardens", "Bamboo Forest Path", "Huangshan Terrace",
            "Forbidden Gardens", "Soaring Towers Avenue",
        ],
        [
            "Beijing Central Station", "Hongqiao Station",
            "Guangzhou South Station", "Chengdu East Station",
        ],
    ),
    (
        "brazil",
        "Brazil",
        "\U0001F1E7\U0001F1F7",
        [
            "Beco do Pão", "Travessa das Flores",
            "Orla Marítima", "Rua dos Coqueiros", "Feira do Mercado",
            "Avenida do Samba", "Rua da Praia", "Largo da Sé",
            "Avenida Paulista", "Mercado Central", "Rua do Comércio",
            "Copacabana Drive", "Ipanema Walk", "Pelourinho Square",
            "Amazônia Road", "Café Valley Road", "Pantanal Trail",
            "Jardim Botânico", "Chapada Drive", "Costa Verde Terrace",
            "Pão de Açúcar Heights", "Cristo Boulevard",
        ],
        [
            "Central do Brasil Station", "Sé Station",
            "Barra Funda Station", "Tietê Station",
        ],
    ),
    (
        "australia",
        "Australia",
        "\U0001F1E6\U0001F1FA",
        [
            "Woolshed Lane", "Outback Track",
            "Coogee Walk", "Harbour Lane", "Fern Gully Road",
            "Royal Parade", "Queen Street Mall", "Collins Lane",
            "Wattle Street", "Shearer's Road", "Stockyard Row",
            "Harbour Bridge Road", "Bondi Terrace", "Federation Square",
            "Red Centre Way", "Barrier Reef Drive", "Murray River Road",
            "Kakadu Terrace", "Blue Mountains Way", "Vineyard Estate",
            "Opera House Gardens", "Skyline Tower Avenue",
        ],
        [
            "Sydney Terminal Station", "Southern Cross Station",
            "Flinders Street Station", "Adelaide Parklands Station",
        ],
    ),
    (
        "canada",
        "Canada",
        "\U0001F1E8\U0001F1E6",
        [
            "Maple Lane", "Trapper's Trail",
            "Lakeshore Walk", "Maple Grove Road", "Harbourfront Way",
            "Rideau Promenade", "Queen's Walk", "Fisherman's Wharf",
            "Prairie Trail", "Timber Road", "Bay Street Row",
            "Mount Royal Avenue", "Granville Island Way",
            "Confederation Boulevard",
            "Aurora Trail", "Rocky Mountain Road", "Maple Ridge Drive",
            "Lake Louise Terrace", "Fundy Coast Way", "Niagara Gardens",
            "Parliament Heights", "Northern Lights Estate",
        ],
        [
            "Toronto Union Station", "Pacific Central Station",
            "Montreal Central Station", "Halifax Terminal Station",
        ],
    ),
    (
        "egypt",
        "Egypt",
        "\U0001F1EA\U0001F1EC",
        [
            "Spice Bazaar Lane", "Nile Fisherman's Row",
            "Corniche Walk", "Palm Grove Road", "Felucca Quay",
            "Luxor Promenade", "Khan Alley", "Papyrus Street",
            "Sphinx Avenue", "Citadel Road", "Nile Corniche Terrace",
            "Pyramid View Road", "Obelisk Square", "Alexandria Harbor Walk",
            "Siwa Oasis Way", "Red Sea Drive", "Desert Caravan Trail",
            "Valley of Kings Road", "Oasis Gardens", "Delta Palm Terrace",
            "Great Pyramid Gardens", "Nile Palace Boulevard",
        ],
        [
            "Ramses Station", "Giza Central Station",
            "Alexandria Station", "Aswan Station",
        ],
    ),
    (
        "uae",
        "United Arab Emirates",
        "\U0001F1E6\U0001F1EA",
        [
            "Souq Lane", "Dhow Harbour Road",
            "Palm Walk", "Marina Promenade", "Deira Market Street",
            "Corniche Boulevard", "Pearl Square", "Falcon Street",
            "Gold Souk Road", "Camel Track Lane", "Mangrove Walk",
            "Sheikh Zayed Road", "Jumeirah Beach Walk",
            "Heritage Village Road",
            "Liwa Desert Way", "Oasis Palm Drive", "Mountain Pass Road",
            "Mangrove Gardens", "Creek Terrace", "Desert Bloom Estate",
            "Skyline Tower Boulevard", "Emerald Palace Heights",
        ],
        [
            "Abu Dhabi Union Station", "Al Quoz Station",
            "Marina Terminal Station", "Desert Gateway Station",
        ],
    ),
]

# The board keeps these two names on every board: the tiles draw the same
# electric and water artwork for them, and a player cannot rename them.
KEEP_NAMES = {"Electric", "City Water"}

STATION_INDICES = [5, 15, 25, 35]

HEADER = """-- Boards.
--
-- A board is the *names* of the 40 spaces. Prices, rents, colour groups,
-- building costs and the order of the tiles are identical on every board, which
-- is why choosing one at the table cannot change a rule - the board only
-- decides what the spaces are called.
--
-- The rows below (`owner_id` null) are the built-in countries, available to
-- everybody. A signed-in player can add their own board from the app: it is
-- written here with their player id as `owner_id`, a `board_id` of
-- `custom_<uuid>`, and it is only ever read back for that player.
--
-- The app never trusts a board row for money: the rent a player pays is read
-- from the space the game screen loaded, and a custom board's numbers come from
-- the built-in board it was copied from. Custom boards only rename spaces.
--
-- Safe to run more than once.

create table if not exists public.game_boards (
  id          serial primary key,
  -- The value a game session stores. Built-ins use their country id
  -- (`india`, `usa`, ...); a player's board uses `custom_<uuid>`.
  board_id    text not null unique,
  name        text not null,
  flag        text not null default '',
  -- Null on the built-in boards; the player id of whoever created it
  -- otherwise. A board with an owner is only offered to that player.
  owner_id    text,
  is_custom   boolean not null default false,
  spaces      jsonb not null,
  cards       jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists game_boards_owner_idx
  on public.game_boards (owner_id);

-- One board per name per player, so a double tap on Save cannot leave two
-- copies of the same board in the picker. Built-ins are exempt: their names
-- are constants and `board_id` already keeps them unique.
create unique index if not exists game_boards_owner_name_idx
  on public.game_boards (owner_id, lower(name))
  where owner_id is not null;

comment on table public.game_boards is
  'Board names (built-in countries and players'' own), read by the app.';

insert into public.game_boards
  (board_id, name, flag, owner_id, is_custom, spaces, cards)
values
"""

FOOTER = """on conflict (board_id) do nothing;

-- A board seeded before the tax squares carried a figure keeps the spaces it
-- was created with, because the insert above only adds a board that is not
-- already there. Income Tax is 200 in every board's own money, so this puts the
-- value on the rows that are missing it - the same way a price sits on every
-- other card. A player's own board is a copy of a built-in one, so it gets the
-- value too, but only while its fourth space is still called Income Tax: a
-- space the player renamed is theirs and is left as it is.
update public.game_boards
   set spaces = jsonb_set(spaces, '{4,price}', '200'::jsonb, true),
       updated_at = now()
 where spaces -> 4 ->> 'name' = 'Income Tax'
   and spaces -> 4 ->> 'price' is null;
"""


def main():
    with open(TEMPLATE, encoding="utf-8") as handle:
        template = json.load(handle)

    spaces = template["spaces"]
    properties = [s for s in spaces if s["type"] == "Property"]
    named = [s for s in properties if s["name"] not in KEEP_NAMES]
    stations = [s for s in named if s["name"].endswith("Station")]

    problems = []
    if len(named) != 26:
        problems.append(f"template has {len(named)} renameable spaces, expected 26")
    if [s["index"] for s in stations] != STATION_INDICES:
        problems.append(f"stations are at {[s['index'] for s in stations]}")

    seen = set()
    for country_id, name, flag, property_names, station_names in COUNTRIES:
        if country_id in seen:
            problems.append(f"duplicate country id {country_id}")
        seen.add(country_id)
        if len(property_names) != 22:
            problems.append(f"{name}: {len(property_names)} property names, expected 22")
        if len(station_names) != len(STATION_INDICES):
            problems.append(f"{name}: {len(station_names)} stations, expected 4")
        for station in station_names:
            if not station.endswith("Station"):
                problems.append(f"{name}: station '{station}' must end with Station")
        for value in property_names + station_names:
            if value in KEEP_NAMES:
                problems.append(f"{name}: '{value}' must keep its name")
        if len(set(property_names + station_names)) != 26:
            problems.append(f"{name}: duplicate space names")

    if problems:
        print("Refusing to write the boards:")
        for problem in problems:
            print("  -", problem)
        return 1

    rows = []
    for country_id, name, flag, property_names, station_names in COUNTRIES:
        renames = {}
        street_spaces = [s for s in named if not s["name"].endswith("Station")]
        for space, new_name in zip(street_spaces, property_names):
            renames[space["name"]] = new_name
        for space, new_name in zip(stations, station_names):
            renames[space["name"]] = new_name

        out_spaces = []
        for space in spaces:
            copy = dict(space)
            copy["name"] = renames.get(copy["name"], copy["name"])
            out_spaces.append(copy)

        cards = {
            deck: [_rename_in_card(text, renames) for text in entries]
            for deck, entries in template.get("cards", {}).items()
        }

        rows.append(
            (
                country_id,
                name,
                flag,
                json.dumps(out_spaces, ensure_ascii=False),
                json.dumps(cards, ensure_ascii=False),
            )
        )

    parts = [HEADER]
    for index, (board_id, name, flag, spaces_json, cards_json) in enumerate(rows):
        separator = "," if index < len(rows) - 1 else "\n"
        parts.append(
            "  ('{board_id}', {name}, {flag}, null, false,\n"
            "   $json${spaces}$json$::jsonb,\n"
            "   $json${cards}$json$::jsonb){sep}\n".format(
                board_id=board_id,
                name=_sql_string(name),
                flag=_sql_string(flag),
                spaces=spaces_json,
                cards=cards_json,
                sep=separator,
            )
        )
    parts.append(FOOTER)

    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("".join(parts))

    size = os.path.getsize(OUTPUT)
    print(f"wrote {os.path.relpath(OUTPUT)} ({size // 1024} KiB, {len(rows)} boards)")
    return 0


def _sql_string(value):
    return "'" + value.replace("'", "''") + "'"


def _rename_in_card(text, renames):
    """Points a card at the same space on this board.

    Longest names first, and through a placeholder, so "X Station" is not
    half-replaced by a shorter name that happens to be a prefix and a new name
    is never rewritten by a later rule.
    """
    for old in sorted(renames, key=len, reverse=True):
        text = text.replace(old, "\u0000" + renames[old] + "\u0000")
    return text.replace("\u0000", "")


if __name__ == "__main__":
    sys.exit(main())
