import json, collections
SCRATCH="/private/tmp/claude-502/-Users-mihailod-Documents-sezam/27b4db58-b28e-4cb0-9dd2-c576cebf3ebd/scratchpad"
data=json.load(open(f"{SCRATCH}/city_counts.json"))

BELGRADE = """beograd|novi beograd|zemun|batajnica|sremcica|borca|zeleznik|barajevo|lazarevac|obrenovac|mladenovac|grocka|surcin|bolec|boljevci|vinca|veliki crljeni|mali mokri lug|veliki mokri lug|kumodraz|vozdovac|cukarica|cukaricka padina|banjica vozdovac|vidikovac|rusanj|ovca|padinska skela|dobanovci|jakovo|ralja|sopot|umka|vrcin|lestane|zuce|pinosava|brestovik|belgrade|bgd|beogard|beogra|beograd 8|beograd0|beogred|beogtad|beoograd|beorad|beograd,karaburm|beograd cukarica|beograd zeleznik|borca - beograd|borua|bg - zarkovo|cerak ii - bgd|taurunum|zad/beo|n b|vreoci|zaklopaca (grocka)|guncati (barajevo)|baric|drazevac|rudovci|beograd (borca)|beograd (resnik)|beograd (kaluderica)|beograd (zarkovo)|beograd (cerak)|beograd (rakovica)|beograd (kotez)|beograd (bezanijska kosa)|beograd (zeleznik)|beograd (bele vode)|beograd (bezanija)|beograd (krnjaca)|beograd (petlovo brdo)"""

VOJVODINA = """novi sad|subotica|zrenjanin|pancevo|sombor|kikinda|ruma|vrsac|becej|senta|sremski karlovci|s. karlovci|backa palanka|odzaci|sremska kamenica|sr. kamenica|sr.kamenica|sr. mitrovica|sremska mitrovica|srem. mitrovica|s.mitrovica|sr .mitrovica|sr.mitrovica|s. mitrovica|apatin|backa topola|indija|novi becej|petrovaradin|kanjiza|nova pazova|stara pazova|kovin|kula|sid|ada|backi petrovac|bezdan|coka|novi knezevac|ruski krstur|padina|palic|bela crkva|beocin|kisac|kovacica|bajmok|backo gradiste|crvenka|kac|lacarak|mali idos|plandiste|selenca|temerin|uzdin|vojka|cantavir|alibunar|backo petrovo selo|bukovac|curug|cortanovci|debeljaca|deliblato|dolovo|durdevo|elemir|futog|golubinci|gibarac|hajducica|horgos|irig|jarkovac|jasa tomic|jabuka|krivaja|kulpin|kucura|lazarevo|ledinci|martonos|meda|mol|novi slankamen|novo miosevo|novo orahovo|obrez|omoljica|opovo|orom|pacir|perlez|pecinci|putinci|rakovac|ratkovo|rumenka|rusko selo|salas|sasinci|silbas|sirig|sivac|sonta|srpski miletic|stanisic|stara moravica|starcevo|tovarisevo|veternik|veliki gaj|veliko srediste|vladimirovac|voganj|calma|adasevci|berkasovo|bac|backi breg|backi monostor|bajsa|banatsko veliko|beska|banovci|s. kula|vrbas / titov vrbas|b. karlovac|ban. karlovac|banat. karlovac|banat. karlovci|banatski karlova|alibunar|sremska mitrovica"""

KOSOVO = """pristina|prizren|pec|dakovica|gnjilane|kosovska mitrovica|urosevac|orahovac|leposavic"""

SERBIA = """nis|kragujevac|sabac|smederevo|krusevac|cacak|pozarevac|valjevo|kraljevo|leskovac|jagodina|bor|loznica|paracin|zajecar|uzice|pirot|gornji milanovac|smed. palanka|smed.palanka|sm palanka|sm. palanka|smeder. palanka|velika plana|vranje|aleksandrovac|vrnjacka banja|prokuplje|majdanpek|arandelovac|ivanjica|negotin|cuprija|aleksinac|despotovac|prijepolje|trstenik|novi pazar|priboj|pozega|knjazevac|kucevo|svilajnac|bajina basta|lebane|petrovac na mlavi|sokobanja|surdulica|vlasotince|arilje|rekovac|vladicin han|kladovo|niska banja|pocekovina|svrljig|zagubica|batocina|bela palanka|blace|bosilegrad|donji milanovac|grabovac|klicevac|koceljeva|kosjeric|kostolac|krupanj|krusar (cuprija)|lajkovac|ljubovija|lucani|parunovac|podunavci|preljina (cacak)|raca|raska|stubica (paracin)|topola|badovinci|bacevac|bojnik|boljevac|bozevac|bradarac|bracevac|brus|bujanovac|cicevac|cajetina|dimitrovgrad|dobra|donja borina|drmno|dudovica|gadzin han|golubac|gruza|jelasnica|krnjevo|lesnica|markovac|misar|moravac|nova varos|pukovac|radinac|ratina (kraljevo)|rataje|resavica|saraorci|selo draskovac|selo ribnica|sevojno|slovac|stamnica|svetozarevo|ub|velika drenova|veliko laole|zabari|zlatibor|poljska rzana|mali zvornik|veliko gradiste|recica (klicevac)|tabanovic|petrovac|vrba|velike livade|s. kosancic"""

CROATIA = """zagreb|split|pula|rijeka|osijek|vukovar|slavonski brod|beli manastir|knin|dubrovnik|varazdin|krizevci|porec|sisak|velika gorica|cakovec|belisce|darda|bobota|borovo naselje|borovo selo|dalj|delnice|dugi rat|fazana|koprivnica|kutina|ludbreg|makarska|metkovic|novi zagreb|novska|omisalj|pazin|rab|rovinj|sibenik|tovarnik|udbina|valpovo|vojnic - rsk|zapresic|nova gradiska|karlovac"""

BOSNIA = """sarajevo|banja luka|bijeljina|mostar|prijedor|tuzla|doboj|zenica|gradiska / bosanska gradiska|srbac|prnjavor|bosanski samac|foca|gorazde|kozarska dubica|teslic|travnik|bluka|bihac|bosanski petrovac|brcko|cazin|derventa|knezevo|kozarac|krupa na uni|laktasi|livno|lukavac|modrica|mrkonjic grad|novi grad|novi travnik|pale|rajlovac|rogatica|sokolac|srbinje|tesanj|visoko|vlasenica|vogosca-sarajev|zavidovici|sarajevo (srpsko sarajevo)|dvorovi|odzak"""

MONTENEGRO = """podgorica|bar|herceg novi|budva|kotor|niksic|pljevlja|ulcinj|bijelo polje|igalo|tivat|cetinje|baosic|becici|meljine|njivice|petrovac na moru"""

SLOVENIA = """ljubljana|maribor|kranj|novo mesto|koper|nova gorica|celje|ptuj|murska sobota|radovljica|bled|menges|trzin|velenje / titovo velenje|zalec|lasko|domzale|kamnik|trbovlje|trzic|ravne na koros.|slovenj gradec|portoroz|pivka|il.bistrica|vipava|sempas|preserje|petrovce|podnart|lenart|ormoz|zidani most|sencur|sentjur|sempeter|skofja loka"""

MACEDONIA = """skopje|bitola|prilep|stip|gevgelija|strumica|kumanovo|ohrid|kocani|titov veles|radovis|kicevo/"""

FOREIGN = {
 "aarhus, danska":"Denmark","amsterdam":"Netherlands","basel":"Switzerland","schaffhausen":"Switzerland",
 "switzerland":"Switzerland","svajcarska":"Switzerland","berlin":"Germany","frankfurt":"Germany",
 "minhen":"Germany","karben, deuts.":"Germany","brussels":"Belgium","budimpesta, madarska":"Hungary",
 "cachan, france":"France","pariz, francuska":"France","gaborone":"Botswana","helsinki":"Finland",
 "kijev, ussr":"Ukraine (USSR)","limasol, kipar":"Cyprus","marlow":"United Kingdom","oxford, england":"United Kingdom",
 "melburn":"Australia","mil sons point":"Australia","moskva, rusija":"Russia","san diego, usa":"USA",
 "san hoze":"USA","washington":"USA","stockholm":"Sweden","toronto, kanada":"Canada",
}

def s(x): return {v.strip() for v in x.split("|") if v.strip()}
REGIONS=[("Belgrade Metro",s(BELGRADE)),("Serbia – Vojvodina",s(VOJVODINA)),("Serbia – Kosovo",s(KOSOVO)),
         ("Serbia – central",s(SERBIA)),("Croatia",s(CROATIA)),("Bosnia and Herzegovina",s(BOSNIA)),
         ("Montenegro",s(MONTENEGRO)),("Slovenia",s(SLOVENIA)),("North Macedonia",s(MACEDONIA))]

tot=collections.Counter(); countries=collections.Counter(); unknown=collections.Counter()
overlap=collections.defaultdict(list)
for name,st in REGIONS:
    for c in st:
        overlap[c].append(name)
dupes={k:v for k,v in overlap.items() if len(v)>1}
if dupes: print("!! city listed in two regions:", dupes)

for key,info in data.items():
    n=info["n"]
    if key=="":
        tot["(not specified)"]+=n; continue
    hit=None
    for name,st in REGIONS:
        if key in st: hit=name; break
    if hit: tot[hit]+=n
    elif key in FOREIGN: tot["Abroad"]+=n; countries[FOREIGN[key]]+=n
    else: unknown[key]+=n; tot["(unclear)"]+=n

users=sum(tot.values())
print(f"\n{'region':28} {'users':>6}  {'share':>6}")
for name,n in tot.most_common():
    print(f"{name:28} {n:6}  {n/users*100:5.1f}%")
print(f"{'TOTAL':28} {users:6}")
print("\nabroad by country:")
for c,n in countries.most_common(): print(f"  {c:20} {n}")
print(f"\nunclear keys ({len(unknown)} keys, {sum(unknown.values())} users):")
for k,n in unknown.most_common(): print(f"  {n:3} {k}")
