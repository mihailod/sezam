import Foundation

/// Hand-approved company merges. **Filtering only.**
///
/// These affect which users a company filter selects and which entries the
/// filter list shows. They never change what a user row displays: a profile
/// that says `Ptt Vukovar` still reads `Ptt Vukovar`, it is merely reachable
/// by ticking `PTT`. The archive is a historical record and the app does not
/// rewrite it.
///
/// Case and diacritics are already handled by `SearchQuery.fold`, so nothing
/// here exists just to join Racunari to Računari. These are the cases folding
/// cannot reach: a quote or a hyphen in one spelling but not the other, a legal
/// suffix ("D.O.O.", "AD"), a descriptive prefix ("Časopis"), or an outright
/// typo. Each was reviewed and approved individually rather than inferred --
/// the automatic matcher also proposed joining Rc Company to Ra Company and
/// Dead Company to Dead Poets Society.
///
/// The first name in each row is the spelling to keep; the rest fold into it.
/// Every entry was checked against the archive, so none of these strings is a
/// guess about what the data contains.
enum UserAliases {

    static let companies: [[String]] = [
        // Tier 1 -- one name spelled two ways: a quote, a hyphen, a
        // legal suffix, a "Časopis" prefix, or a typo.
        ["Računari", "Časopis \"Racunari\"", "Raüunari"],
        ["Institut \"mihajlo Pupin\"", "Institut Mihajlo Pupin",
         "Ei Pupin", "Ins.mihajlo Pupin,lab. Za Auto", "pupin terminali", "IMP"],
        ["Ibis Sys", "Ibis-sys"],
        ["Megaplast Promet", "Megaplast-promet"],
        ["VREME", "Časopis \"vreme\""],
        ["Lasta", "Sp Lasta", "SP \"Lasta\"", "Sp Lasta Služba Razvoja"],
        ["Dp \"intex\"", "intex"],
        ["PORSCHE", "Porsche Engineering"],
        ["\"mikrosam\" - Prilep", "\"mikrosam\" -prilep"],
        ["Bit - Software Design", "Bit Software Design"],
        ["Dekik Corporation.", "Dekik Coorporation."],
        ["Dp Din \"fabrika Duvana\" Nis", "Dp Din Fabrika Duvana Nis"],
        ["Elektrotehnički Fakultet Beogr", "Elektrotehnicki Fakultet, Beog", "Etf Beograd"],
        ["Institut \"jaroslav Cerni\"", "Institut Jaroslav Cerni"],
        ["Jkp \"vodovod I Kanalizacija\"", "Jkp \"vodovod I Kanalizacija\" N"],
        ["KBC Kragujevac", "KBC-Kragujevac"],
        ["Mds Informacijski Inženjering", "Mds Informacijski Inžinjering"],
        ["NIS Energogas", "NIS \"ENERGOGAS\"", "Energogas Beograd"],
        ["Radio B92", "Radio B-92"],
        ["Unis Unidata", "Unis-unidata"],
        ["PAKOM AD", "PAKOM A.D."],
        ["LIMES", "Limes D.O.O."],
        ["SARTID AD", "SARTID 1913", "\"sartid 1913 Institut\""],

        // Tier 2 -- a short name and the longer names containing it.
        // Approved individually; Računari, Mikro, Progres, Abacus and
        // Telekom were reviewed and rejected as unrelated firms.
        ["PTT", "Ptt Crne Gore", "Jp Ptt Saobracaja Crne Gore", "ptt krusevac", "Rj Ptt \"sombor\"", "Ptt Slavonski Brod", "Rj Ptt Saobraćaja \"subotica\"", "Ptt Vukovar", "Ptt Doboj", "Zajednica Jugoslovenskih Ptt", "Ptt Sabac", "Ptt Cacak", "Ptt Baranja", "Rj Ptt Sabac", "PTT Beli Manastir", "JP PTT CRNE GORE", "P Ptt Saobracaja \"krajina\" B.l", "Rj Ptt Prnjavord", "Ptt Tuzla", "Ptt Livno", "PTT ROMANIJA", "JPPTT RJ-Krusevac", "Pptt"],
        ["Tanjug", "Agencija Tanjug - Demo", "Na Tanjug"],
        ["tIGAR", "Tigar Pirot"],
        ["Imtel", "Imtel Computers", "Imtel - Beograd"],
        ["Zli Kablovi", "Zli Kablovi/KTM"],
        ["Pc Press", "Pc Press, Izdavačko Preduzeće"],
        ["Hemofarm", "Hemofarm Koncern"],
        ["Srbijasume", "Jp Srbijašume - Beograd"],
        ["Elektrosumadija", "Elektrosumadija Kragujevac"],
        ["Srbijanka", "Srbijanka Beograd"],
        ["Microsys", "Ms Microsys Beograd"],
        ["Zitobacka", "Zitobacka Kula"],
        ["Petrel", "Petrel - Zemun"],
        ["Merkur", "Merkur-boje I Lakovi"],
        ["Bigz", "Bigz - Tajne"],
        ["Videophone", "Videophone, Luja Adamica 26d"],
        ["Cet", "Cet (computer Equipment & Trad"],
        ["OSA", "Osa - Fom, D.o.o.", "Osa-računarski Inženjering"],
        ["Rts", "PGP RTS", "Radio Televizija Srbije", "Iii Kanal"],
        ["Energoprojekt", "Energodata", "Energoprojekt-energodata", "Energoprojekt Entel Dd"],
        ["Comtrad", "Comtrad Yu", "Comtrad-kragujevac"],
        ["Medifarm", "Medifarm Dd", "Medifarm Inzenjering"],

        // Second company sweep: a garbled č, an abbreviation (ETF), a city or
        // legal suffix, a descriptive prefix ("Agencija"), or a name cut off at
        // the 30-character field limit.
        ["Beomedicina R&D", "Beomedicnr&d", "Beomecina"],
        ["Sumarski Fakultet", "Šumarski Fakultet Beograd"],
        ["Data3 D.d.", "Data3 D.d. Beograd"],
        ["U.S. Information Service", "U.s. Information Service Belgr"],
        ["Icom Export", "Icom Co. Export - Imt Beograd", "Icom Export Bgd"],
        ["Beogradska Pekarska Industrija", "Beogradska Pekarska Industrij",
         "Bpi Beogradska Pekarska Indust"],
        ["Jugopetrol", "Nis-jugopetrol, Beograd"],
        ["Orka", "Agencija Orka"],

        // Regional branches folded into the parent, as with PTT: the regional
        // Elektrodistribucija companies, and the Zastava group.
        ["Elektrodistribucija", "Elektrodistribucija \"kikinda\"", "Elektrodistribucija Cuprija", "Elektrodistribucija Herceg-nov", "Elektrodistribucija Pančevo", "Elektrodistribucija Ruma", "Elektrodistribucija Sombor", "Elektrodistribucija Sremska Mi", "Elektrodistribucija-leskovac"],
        ["Zastava", "Zastava automobili", "Zastava Iveco Kamioni", "Zastava Promet - Beograd", "Zastava Promet Kragujevac"],
        ["Karalić Co.", "Karalic Co. Rj:teletel Communi", "Karalic Co. Tele - Data'co. In", "Karalic Corporation. Inc.,", "Mandic & Karalic Computers. Lt"],
        ["FTN Novi Sad", "Ftn Iniu", "Ftn Institut Za Ram", "Ftn, Noi Za Ram"],
        ["Institut \"Vinča\"", "INN \"VINČA\"", "Institut \"vinca\" Laboratorija", "Institut Za Nuklearne Nauke \"v"],
        ["Ei Niš", "Ei Informatika Dd Nis", "Ei Dp Racunari"],
        ["Radio Index", "Radio Index, 88.9 MHz"],
        ["Televizija Banja Luka", "Televizija Banja Luka,biznis K"],
        ["Radio Pingvin", "Pingvin D.o.o."],
        ["Telekom Srbija", "TELEKOM"],
        ["Pobeda", "Pobeda Projekt"],
        ["JKP Gradske Pijace, VEGA Lab", "VEGA Lab"],
        ["Commitments BBS", "Commitments Corp."],
        // Same member behind both spellings, confirmed from member data.
        ["Odeljenje za Alkoholizam Sombor", "Odeljenje za alkoholizam", "Odeljenje Za Alkoholizam Sombo"],
        ["Ekonomski Fakultet Niš", "Ekonomski Fakultet,nis", "Ekonomski fakultet"],
        // From the member-data sweep: same person or same city behind both spellings.
        ["SportNET Agency", "Sportnet Agency", "Dizel SportNET Agency"],
        ["Fabrika Šećera", "Fabrika Šećera \"bačka\"", "Fabrika Secera Vrbas"],
        ["Elektrokosmet", "J.P. Elektrokosmet", "J.p. Elektrokosmet Pri[tina"],
        ["Apatinska Pivara", "Apatinska Pivara Apatin"],
        ["Informatički Inženjering Zrenjanin", "Mpa Dp Za Informatički Inženje", "Sektor Za Informatički Inženje"],
        ["Miško / Srbija Promet Vlasotince", "Misko-promet", "Pp\"srbija Promet\""],
        ["Stankom", "Stankom Korporacija", "Stankom-osiguranje-beograd"],
        ["Tehnoprojekt Zenica", "Premiz-tehnoprojekt"],
        ["Politika", "Nip Politika Weekly", "tv politika"],
        ["Shit Inc.", "Insane Shit INC.", "My shit INC."],
        ["Hyperopia", "Hyperopia [code]", "Hyperopia [music]", "Hyperopia [public Relations]"],
    ]

    /// Company names shared by unrelated firms. These cannot be separated by
    /// spelling -- the members typed the identical name -- so the filter adds
    /// the member's city: "Infotrade Priština", "Infotrade Sremčica".
    /// Established from member data, not guessed from the name.
    static let companiesSplitByCity: [String] = ["Infotrade"]
    static let companySplitKeys: Set<String> = Set(companiesSplitByCity.map { fold($0) })

    /// Display labels for the filter list, where the automatic pick is poor.
    ///
    /// The label normally comes from the most frequent spelling, which usually
    /// gets the diacritics right (Niš beats Nis) but has no idea about
    /// capitalisation: it happily returns `tIGAR`, `Bigz` or `Rts`, and when a
    /// cluster is one user against one user it picks by alphabet.
    ///
    /// Filter list only. A user row still shows what that member typed.
    ///
    /// Each row is `[anchor, label]`. The anchor is a spelling that really
    /// occurs in the archive, not the label itself: folding preserves quotes,
    /// so `DP Intex` would never find the group whose only spelling is
    /// `Dp "intex"`.
    static let companyLabels: [[String]] = [
        ["Institut \"mihajlo Pupin\"", "Institut \"Mihajlo Pupin\""],
        ["tIGAR", "Tigar"],
        ["Vojni Servis Nbj", "Vojni Servis NBJ"],
        ["BANE SEKULIC", "Bane Sekulic"],
        ["Bigz", "BIGZ"],
        ["Dp Din \"fabrika Duvana\" Nis", "DP DIN Fabrika Duvana Niš"],
        ["Dp \"intex\"", "DP Intex"],
        ["Institut \"jaroslav Cerni\"", "Institut \"Jaroslav Černi\""],
        // Both members' entries name Novi Sad's utility; one of them lived in Belgrade.
        ["Jkp \"vodovod I Kanalizacija\"", "JKP \"Vodovod i Kanalizacija\" Novi Sad"],
        ["Rts", "RTS"],
        ["Ro \"makarije Čudotvorac\"", "RO \"Makarije Čudotvorac\""],
        ["Srbijasume", "Srbijašume"],
        ["Sumarski Fakultet", "Šumarski Fakultet"],
        ["Pc Press", "PC Press"],
        ["Ekonomski Fakultet,nis", "Ekonomski Fakultet Niš"],
        ["Elektrotehnički Fakultet Beogr", "ETF Beograd"],
        ["Beomedicina R&d", "Beomedicina R&D"],
        // Stray bytes from line noise; there is no clean spelling to merge with.
        ["Sinko-enĘterijeri", "Sinko Enterijeri"],
        ["H & M  InternationalÚ", "H & M International"],
        // Faculties go by their usual short names.
        ["Etf Podgorica", "ETF Podgorica"],
        // Split apart after member data showed different cities and people.
        ["Bbsoft", "BBSoft"],
        ["Vet.fakultet Zad Za Radiologij", "Veterinarski Fakultet Sarajevo"],
        ["Katedra Za Biologiju Vet. Fak.", "Veterinarski Fakultet Beograd"],
        ["Rudarsko Geološki Fakultet", "Rudarsko-geološki Fakultet Tuzla"],
        ["Rgf-beograd Institut Za Hidrog", "Rudarsko-geološki Fakultet Beograd"],
        ["Institut Za Crnu Metalurgiju", "Institut za Crnu Metalurgiju"],
    ]

    static let cityLabels: [[String]] = [
        ["Petrovac Na Moru", "Petrovac na Moru"],
        ["Kičevo/", "Kičevo"],
    ]

    /// Hand-approved city merges. Same rules as `companies`: filtering only,
    /// user rows keep what the member typed.
    static let cities: [[String]] = [
        // Zemun was written as its own town, as a district of Belgrade, and
        // once with a stray Ź. Zemun Polje is strictly a separate settlement,
        // merged here by explicit decision rather than by the matcher.
        ["Zemun", "Beograd-zemun", "Zemun Polje", "Beograd, Zemun", "ZemunŹo"],

        // Belgrade proper: typos, plus the inner districts a reader would just
        // call Belgrade -- Čukarica, Voždovac, Banjica, Banovo Brdo, Karaburma,
        // Čukarička Padina. Outer districts get their own "Beograd (X)" below.
        ["Beograd", "Beograd-", "Beogradd", "Banovo Brdo", "Banovo Brdo Beog",
         "Beogard", "Beogra", "Beograd 8", "Beograd Čukarica", "Beograd0",
         "Beograd,Karaburm", "Beogred", "Beogtad", "Beoograd", "Beorad",
         "Banjica Vozdovac", "Voždovac", "Čukarica", "Čukarička Padina", "Belgrade"],

        ["Novi Beograd", "N. Beograd", "N.beograd", "Novi  Beograd", "Beonovi Beograd"],

        // "Sremska Mitrovica" is a canonical name, not an archive spelling --
        // nobody typed it in full, every record is truncated. A keep name only
        // has to be consistent, not present, so it stands as the label for the
        // group. Kosovska Mitrovica is a different city and stays out.
        ["Sremska Mitrovica", "Sremska Mitrovi", "Sremska Mitrovic",
         "Srem. Mitrovica", "Sr. Mitrovica", "Sr.mitrovica", "Sr .mitrovica",
         "S. Mitrovica", "S.mitrovica"],
        ["Sremska Kamenica", "Sremska Kamenic", "Srem. Kamenica", "Sremsk. Kamenica",
         "Sr. Kamenica", "Sr.kamenica"],
        ["Sremski Karlovci", "Srem. Karlovci", "Sr. Karlovci", "Sr.karlovci",
         "S. Karlovci"],

        // Reviewed batch: spacing and punctuation variants, abbreviated first
        // words, and entries corrupted by line noise. Several keep names are
        // canonical rather than archive spellings -- Smederevska Palanka and
        // Banatski Karlovac were never typed in full, and the Belgrade
        // districts get a "Beograd (X)" form that no member used.
        //
        // Deliberately NOT merged: "Karlovac" (Croatia) is a different city
        // from Banatski Karlovac, and "Borovo Selo" is not Bačko Petrovo Selo.
        // Also reviewed and left alone: "Vrba", "Ograd" and "Turčin" are real
        // places, not typos of Vrbas, Beograd and Surčin; "S. Kula" and bare
        // "Brod" cannot be tied to one place.
        ["Banja Luka", "Banjaluka", "Banjluka"],
        ["Smederevska Palanka",
         "Smed. Palanka", "Smed.palanka", "Smeder. Palanka", "Sm. Palanka", "Sm Palanka"],
        ["Herceg Novi", "Herceg-novi"],
        // Belgrade districts. Continuous built-up city, out to roughly 12 km:
        // the same character as Čukarica or Voždovac, which fold into plain
        // Beograd. Sremčica (18 km), Umka (22 km) and Sopot (40 km) are
        // separate settlements with their own centres and stay standalone.
        ["Beograd (Borča)", "Beograd-borča", "Beograd - Borča", "Beograd, Borča",
         "Borca - Beograd", "Borča", "Borüa"],
        ["Beograd (Cerak)", "Beograd Cerak", "Cerak Beograd", "Cerak",
         "Cerak Ii - Bgd"],
        ["Beograd (Resnik)", "Beograd-resnik", "Resnik"],
        ["Beograd (Rakovica)", "Rakovica, Beogra", "Rakovica", "Rakovica Bgd"],
        ["Beograd (Kotež)", "Kotež-beograd", "Kotež"],
        ["Beograd (Krnjača)", "Krnjača Beograd"],
        ["Beograd (Petlovo Brdo)", "Petlovo Brdo"],
        ["Beograd (Bele Vode)", "Beograd, Bele Vo"],

        // Separate settlements: the Beograd-prefixed spellings fold into the
        // town's own name, not the other way round.
        ["Sremčica", "Beograd-Sremčica"],
        ["Sopot", "Beograd-sopot"],
        ["Umka", "Beograd Umka"],
        ["Beograd (Žarkovo)", "Beograd Žarkovo", "Beograd-žarkovo", "Žarkovo",
         "Bg - Zarkovo"],
        ["Beograd (Železnik)", "Zeleznik-Beograd", "Železnik Beograd",
         "Beograd Železnik", "Železnik"],
        ["Kosovska Mitrovica", "Kos. Mitrovica", "Kos.mitrovica", "Kosovska Mitrov"],
        ["Stara Pazova", "St. Pazova"],
        ["Veliko Gradište", "Vel. Gradište"],
        ["Banatski Karlovac",
         "Banat. Karlovac", "Ban. Karlovac", "B. Karlovac", "Banatski Karlova",
         "Banat. Karlovci"],
        ["Bačko Petrovo Selo", "B.p.selo"],
        ["Kragujevac", "Kragujevacd", "KragujevacŰ{m"],
        ["Kotor", "Kotorat"],
        ["Zenica", "Zenica˝ů"],
        ["Prijepolje", "Prijepolje0"],

        // Single-character slips and competing transliterations. Serbian
        // spelling is the canonical form, with one deliberate exception:
        // Skopje keeps the Macedonian spelling rather than Serbian "Skoplje".
        // Petrovgrad was Zrenjanin's name from 1935 to 1946 -- long before
        // Sezam, so unlike Titov Vrbas it gets no dual label.
        ["Zrenjanin", "Zrenjnin", "Petrovgrad"],
        ["Priština", "Prishtina"],
        ["Skopje", "Skoplje", "Skopje, Mk"],
        ["Inđija", "Inđjija"],
        ["Kanjiža", "Kanijiža"],
        // đ written as dj. The search index expands that pair, but the facet
        // fold maps đ to d, so the two spellings key apart and need this row.
        ["Beograd (Kaluđerica)", "Kaluđerica", "Kaludjerica", "Kaluđerica (bg)"],
        ["Pariz, Francuska", "Pariz, France", "Paris, France"],
        ["Beograd (Bežanijska Kosa)", "Bežanijska Kosa", "Bežaniska Kosa"],
        // Bežanija and Bežanijska Kosa are neighbouring but distinct districts.
        ["Beograd (Bežanija)", "Bežanija"],

        // Region or country appended to an otherwise identical name.
        ["Batajnica", "Batajnica(bgd)", "Batajnica, Bg"],
        ["Barajevo", "Barajevo, Bg."],
        ["Maribor", "Maribor, Si"],
        ["Limasol, Kipar", "Limassol", "Limassol Cyprus"],
        ["Rumenka", "Rumenka (ns)"],
        ["Zaklopača (Grocka)", "Zaklopača", "Zaklopača, Groc"],
        ["Počekovina", "Selo Počekovina"],
        ["Užice", "Užice Krčagovo"],

        // Renamed while Sezam was running, so members registered under both
        // names. The label carries both rather than picking one side of the
        // rename.
        ["Vrbas / Titov Vrbas", "Vrbas", "Titov Vrbas", "T.vrbas"],
        ["Velenje / Titovo Velenje", "Velenje", "T.velenje"],
        ["Gradiška / Bosanska Gradiška", "Gradiška", "Bos. Gradiška"],

        // Villages written together with their nearby town. The village is
        // the place; the town goes in parentheses. The towns themselves --
        // Čačak, Ćuprija, Paraćin, Kraljevo, Kličevac, Barajevo -- stay put.
        ["Preljina (Čačak)", "Čačak-preljina", "Preljina"],
        ["Krušar (Ćuprija)", "Ćuprija, Krušar", "Krusar"],
        ["Stubica (Paraćin)", "Stubica Paraćin", "Stubica"],
        ["Ratina (Kraljevo)", "Ratina, Kraljevo"],
        ["Rečica (Kličevac)", "Rečica-Kličevac"],
        ["Guncati (Barajevo)", "Barajevo Guncate"],

        // Srpsko Sarajevo was a separate post-war municipality and stays its
        // own entry; the label only makes it sort next to Sarajevo.
        ["Sarajevo (Srpsko Sarajevo)", "Sr. Sarajevo"],

        // Five different Petrovacs. Bare "Petrovac" and "Bački Petrovac" are
        // deliberately left alone.
        ["Petrovac na Mlavi", "Petrovac Na Mlav", "Petrovac N/ml"],
        ["Bosanski Petrovac", "Bos.petrovac"],
        ["Banovci", "Stari Banovci", "Novi Banovci", "Banovci-Dunav"],

        // Kosovo towns written with the Albanian form or with dj for đ. The
        // Serbian name is canonical, as with Priština.
        ["Đakovica", "Djakovica"],
        ["Gnjilane", "Gjilan"],

        // Foreign cities: Serbian name, then the country -- the same form as
        // Pariz, Francuska.
        ["Budimpešta, Mađarska", "Budimpesta", "Budapest"],
        ["Toronto, Kanada", "Toronto Canada", "Toronto Ont Can"],

        // Letters lost in transmission.
        ["Nova Gradiška", "Nova Giska"],
        ["Radoviš", "Radovič"],
    ]

    private static func fold(_ s: String) -> String {
        SearchQuery.fold(s).lowercased()
    }

    /// Variant folded key -> the folded key it merges into.
    static func keyMap(for field: FilterSection) -> [String: String] {
        field == .company ? companyKeyMap : cityKeyMap
    }

    /// Folded key -> the spelling to display, overriding the majority vote.
    /// Needed because a merged cluster is often 1 user against 1 user, where
    /// the majority rule would pick by alphabet and land on the typo.
    static func labelMap(for field: FilterSection) -> [String: String] {
        field == .company ? companyLabelMap : cityLabelMap
    }

    private static let companyKeyMap = buildKeyMap(companies)
    private static let cityKeyMap = buildKeyMap(cities)
    private static let companyLabelMap =
        buildLabelMap(companies, companyLabels, companyKeyMap)
    private static let cityLabelMap =
        buildLabelMap(cities, cityLabels, cityKeyMap)

    private static func buildKeyMap(_ clusters: [[String]]) -> [String: String] {
        var m: [String: String] = [:]
        for cluster in clusters {
            guard let keep = cluster.first else { continue }
            let target = fold(keep)
            for variant in cluster.dropFirst() { m[fold(variant)] = target }
        }
        return m
    }

    private static func buildLabelMap(_ clusters: [[String]],
                                      _ overrides: [[String]],
                                      _ keys: [String: String]) -> [String: String] {
        var m: [String: String] = [:]
        for cluster in clusters {
            guard let keep = cluster.first else { continue }
            m[fold(keep)] = keep
        }
        // Applied second so a hand-written label wins over the kept spelling.
        for row in overrides {
            guard row.count == 2 else { continue }
            let k = fold(row[0])
            m[keys[k] ?? k] = row[1]
        }
        return m
    }
}
