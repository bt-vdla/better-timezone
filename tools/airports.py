# Builds Skies/airports.csv from OurAirports' airports.csv (public domain, ourairports.com).
# Run: python3 -I tools/airports.py path/to/ourairports/airports.csv > Skies/airports.csv
# Each row: IATA, lat, lon, size (0 large, 1 medium), country, city, time zone.
# The time zone is filled only where it's certain offline; Skies looks the rest up on Apple Maps when asked.
import csv, math, re, sys, collections
from datetime import datetime
from zoneinfo import ZoneInfo

def coords(s):
    m = re.match(r'([+-]\d{4,6})([+-]\d{5,7})', s)
    def conv(x, deg):
        sign = -1 if x[0] == '-' else 1
        x = x[1:]
        return sign * (int(x[:deg]) + int(x[deg:deg + 2]) / 60 + int(x[deg + 2:] or 0) / 3600)
    return conv(m.group(1), 2), conv(m.group(2), 3)

zones = collections.defaultdict(list)
for line in open('/usr/share/zoneinfo/zone.tab'):
    if line.startswith('#'):
        continue
    f = line.rstrip('\n').split('\t')
    lat, lon = coords(f[1])
    zones[f[0]].append((f[2], lat, lon))

# The country's main zone, as Skies' countries.csv has it.
main = dict(l.strip().split(',') for l in open('Skies/countries.csv') if not l.startswith('#'))

def offsets(tz):
    z = ZoneInfo(tz)
    return tuple(datetime(2026, m, 15, 12, tzinfo=z).utcoffset() for m in (1, 7))

US = {'Eastern': 'America/New_York', 'Central': 'America/Chicago', 'Mountain': 'America/Denver', 'Pacific': 'America/Los_Angeles'}
US_STATES = {
    'Eastern': 'CT DE DC FL GA IN KY ME MD MA MI NH NJ NY NC OH PA RI SC VT VA WV',
    'Central': 'AL AR IL IA KS LA MN MS MO NE ND OK SD TN TX WI',
    'Mountain': 'CO ID MT NM UT WY',
    'Pacific': 'CA NV OR WA',
}
US_STATE = {s: US[k] for k, v in US_STATES.items() for s in v.split()}
US_STATE.update({'AZ': 'America/Phoenix', 'AK': 'America/Anchorage', 'HI': 'Pacific/Honolulu'})
US_CITY = {  # states split by a line
    'knoxville': 'America/New_York', 'chattanooga': 'America/New_York', 'blountville': 'America/New_York', 'bristol': 'America/New_York',
    'paducah': 'America/Chicago', 'owensboro': 'America/Chicago', 'bowling green': 'America/Chicago',
    'pensacola': 'America/Chicago', 'panama city': 'America/Chicago', 'valparaiso': 'America/Chicago', 'panama city beach': 'America/Chicago',
    'el paso': 'America/Denver', 'evansville': 'America/Chicago', 'iron mountain': 'America/Chicago', 'iron mountain kingsford': 'America/Chicago',
    'dickinson': 'America/Denver', 'rapid city': 'America/Denver', 'scottsbluff': 'America/Denver', 'lewiston': 'America/Los_Angeles',
    'adak island': 'America/Adak', 'adak': 'America/Adak',
}
CA_PROV = {'ON': 'America/Toronto', 'QC': 'America/Toronto', 'MB': 'America/Winnipeg', 'SK': 'America/Regina', 'AB': 'America/Edmonton',
           'BC': 'America/Vancouver', 'NB': 'America/Halifax', 'NS': 'America/Halifax', 'PE': 'America/Halifax', 'NL': 'America/St_Johns',
           'YT': 'America/Whitehorse', 'NT': 'America/Edmonton', 'NU': 'America/Iqaluit'}
CA_CITY = {'cranbrook': 'America/Edmonton', 'fort st. john': 'America/Dawson_Creek', 'dawson creek': 'America/Dawson_Creek',
           'happy valley-goose bay': 'America/Goose_Bay', 'goose bay': 'America/Goose_Bay', 'wabush': 'America/Goose_Bay', 'churchill falls': 'America/Goose_Bay',
           'rankin inlet': 'America/Rankin_Inlet', 'baker lake': 'America/Rankin_Inlet', 'arviat': 'America/Rankin_Inlet',
           'cambridge bay': 'America/Cambridge_Bay', 'kugluktuk': 'America/Cambridge_Bay', 'gjoa haven': 'America/Cambridge_Bay',
           'kenora': 'America/Winnipeg', 'red lake': 'America/Winnipeg', 'sioux lookout': 'America/Winnipeg', 'les îles-de-la-madeleine': 'America/Halifax'}
AU_STATE = {'NSW': 'Australia/Sydney', 'ACT': 'Australia/Sydney', 'VIC': 'Australia/Melbourne', 'QLD': 'Australia/Brisbane', 'SA': 'Australia/Adelaide',
            'WA': 'Australia/Perth', 'TAS': 'Australia/Hobart', 'NT': 'Australia/Darwin'}
AU_CITY = {'broken hill': 'Australia/Broken_Hill', 'lord howe island': 'Australia/Lord_Howe'}

ID_ZONE = {**{r: 'Asia/Jakarta' for r in 'AC SU SB RI KR JA SS BB BE LA JK JB JT YO JI BT KB KT'.split()},
           **{r: 'Asia/Makassar' for r in 'BA NB NT KS KI KU SA ST SG SN SR GO'.split()},
           **{r: 'Asia/Jayapura' for r in 'MA MU PA PB PD PE PS PT'.split()}}
# Countries whose zones follow their regions; elsewhere the nearest zone city in the country is right.
BY_REGION = {
    'CN': lambda region, city: 'Asia/Shanghai',   # one official time
    'ES': lambda region, city: 'Atlantic/Canary' if region == 'ES-CN' else 'Europe/Madrid',
    'PT': lambda region, city: 'Atlantic/Azores' if region == 'PT-20' else 'Europe/Lisbon',
    'NZ': lambda region, city: 'Pacific/Chatham' if city in ('te one', 'chatham islands') else 'Pacific/Auckland',
    'ID': lambda region, city: ID_ZONE.get(region.split('-')[-1], ''),
}
# Big countries where the nearest zone city can be the wrong side of a line: only trust it up close.
CAREFUL = {'RU', 'BR', 'MX', 'KZ'}

def km(a, b, c, d):
    r = math.pi / 180
    x = math.sin((c - a) * r / 2) ** 2 + math.cos(a * r) * math.cos(c * r) * math.sin((d - b) * r / 2) ** 2
    return 2 * 6371 * math.asin(min(1, math.sqrt(x)))

def zone_for(cc, region, city, lat, lon):
    city = city.lower()
    if cc == 'US':
        return US_CITY.get(city) or US_STATE.get(region.split('-')[-1], '')
    if cc == 'CA':
        return CA_CITY.get(city) or CA_PROV.get(region.split('-')[-1], '')
    if cc == 'AU':
        return AU_CITY.get(city) or AU_STATE.get(region.split('-')[-1], '')
    if cc in BY_REGION:
        return BY_REGION[cc](region, city)
    zs = zones.get(cc, [])
    if not zs:
        return main.get(cc, '')
    if len({offsets(z[0]) for z in zs}) == 1:
        return main.get(cc, zs[0][0])
    # Right at a time-zone city (Moscow, Novosibirsk, Manaus): that's certainly its zone.
    near = min(zs, key=lambda z: km(lat, lon, z[1], z[2]))
    return near[0] if cc not in CAREFUL or km(lat, lon, near[1], near[2]) <= 60 else ''

rows = [r for r in csv.DictReader(open(sys.argv[1], encoding='utf-8'))
        if r['type'] in ('large_airport', 'medium_airport') and r['scheduled_service'] == 'yes' and len(r['iata_code']) == 3]
print('# OurAirports (ourairports.com), public domain: IATA, latitude, longitude, size (0 large, 1 medium), country, city, time zone (empty: look it up)')
for r in sorted(rows, key=lambda r: r['iata_code']):
    lat, lon = float(r['latitude_deg']), float(r['longitude_deg'])
    city = (r['municipality'] or r['name']).replace(',', ' ').strip()
    tz = zone_for(r['iso_country'], r['iso_region'], city, lat, lon)
    print(f"{r['iata_code']},{round(lat, 3)},{round(lon, 3)},{0 if r['type'] == 'large_airport' else 1},{r['iso_country']},{city},{tz}")
