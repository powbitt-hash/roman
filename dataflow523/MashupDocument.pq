[StagingDefinition = [Kind = "FastCopy"]]
section Section1;
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "Cennik_Majcichov_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared Cennik_Majcichov = let
  Source = Lakehouse.Contents(null),
  Navigation = Source{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  #"Navigation 1" = Navigation{[lakehouseId = "40a03b51-8bc8-4154-880a-b31f58231c00"]}[Data],
  #"Navigation 2" = #"Navigation 1"{[Id = "Cennik_Majcichov", ItemKind = "Table"]}[Data]
in
  #"Navigation 2";
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "SPA MAJ_523_VyrobneObjednavky_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared #"SPA MAJ_523_VyrobneObjednavky" = let
  Source = Lakehouse.Contents(null),
  Navigation = Source{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  #"Navigation 1" = Navigation{[lakehouseId = "a31bc90d-0406-46ab-b4c5-88c54250fdd9"]}[Data],
  #"Navigation 2" = #"Navigation 1"{[Id = "SPA.MAJ_523_VyrobneObjednavky", ItemKind = "View"]}[Data],

  // 1. PRIDANIE INDEXU (Proti duplicitam)
  #"Added Index" = Table.AddIndexColumn(#"Navigation 2", "Index_Pre_Deduplikaciu", 0, 1, Int64.Type),

  // 1. STARA LOGIKA
  #"Added custom" = Table.AddColumn(#"Added Index", "Kod_Model_Old", each try Text.Start(Text.Split([MMITDS], " "){3}, 2) otherwise null),
  #"Added custom 1" = Table.AddColumn(#"Added custom", "Kod_Drevina_Old", each try Text.Start(Text.Split([MDITDS], " "){2}, 2) otherwise null),
  #"Added custom 2" = Table.AddColumn(#"Added custom 1", "Kod_Kvalita", each try Text.Start(Text.Split([MMITDS], " "){4}, 4) otherwise null),

  // Prepojenie na Cennik
  #"Merged queries" = Table.NestedJoin(#"Added custom 2", {"MMPRGP", "Kod_Model_Old", "Kod_Drevina_Old", "Kod_Kvalita"}, Cennik_Majcichov, {"MMPRGP", "Kod_Model", "Kod_Drevina", "Kod_Kvalita"}, "Cennik_Majcichov", JoinKind.LeftOuter),
  #"Expanded Cennik_Majcichov" = Table.ExpandTableColumn(#"Merged queries", "Cennik_Majcichov",
      {"Dlzka_Min", "Dlzka_Max", "Cena_FY24", "Cena_FY25", "Cena_FY26"},
      {"Dlzka_Min", "Dlzka_Max", "Cena_FY24", "Cena_FY25", "Cena_FY26"}),

  // 2. VYPOCET CIEN
  // OPRAVA (ErrorCode 10277): v M plati null >= 5  ->  null  a  true and null  ->  null,
  // takze prazdne MMDIM1 alebo prazdna Dlzka_Max v cenniku zhodili cely dotaz.
  // Vsetky tri hodnoty sa teraz kontroluju na null EST PRED porovnanim.
  #"Added custom 3" = Table.AddColumn(#"Expanded Cennik_Majcichov", "Final_Cena_FY26", each
    let
      d = [MMDIM1],
      lo = [Dlzka_Min],
      hi = [Dlzka_Max]
    in
      if d = null or lo = null or hi = null then null
      else if d >= lo and d <= hi then [Cena_FY26]
      else null),
  #"Added custom 4" = Table.AddColumn(#"Added custom 3", "Final_Cena_FY25", each
    let
      d = [MMDIM1],
      lo = [Dlzka_Min],
      hi = [Dlzka_Max]
    in
      if d = null or lo = null or hi = null then null
      else if d >= lo and d <= hi then [Cena_FY25]
      else null),

  // 3. LOGIKA PRE DREVINY
  #"Added custom 9" = Table.AddColumn(#"Added custom 4", "Cislo_Kvality", each try Number.From(Text.Middle([Kod_Kvalita], 1, 1)) otherwise 0),
  #"Added custom 10" = Table.AddColumn(#"Added custom 9", "Kod_Drevina_Full", each try Text.Start(Text.Split([MMFUDS], " "){2}, 2) otherwise ""),

  #"Added custom 11" = Table.AddColumn(#"Added custom 10", "Kluc_Drevina", each if [MMPRGP] = "P31" or [MMPRGP] = "P28" then
    if [Cislo_Kvality] > 2 then "JS_HNEDY" else "JS_BIELY"
  else if [MMPRGP] = "P27" then
    if [Cislo_Kvality] > 4 then "BREZA_KRAJANA" else "BREZA_LUPANA"
  else if [MMPRGP] = "P25" then "ORECH"
  else if [MMPRGP] = "P26" then "BUK"
  else if [MMPRGP] = "P29" then
    // OPRAVA: Text.Contains(null, "V") vracia null -> "if null" by zhodilo dotaz
    // (Kod_Kvalita je null vzdy, ked MMITDS nema aspon 5 slov).
    (let kv = if [Kod_Kvalita] = null then "" else [Kod_Kvalita] in
     if [Kod_Drevina_Full] = "HE" and Text.Contains(kv, "V") then "DUB_V" else "DUB")
  else "OTHER"),

  #"Merged queries 1" = Table.NestedJoin(#"Added custom 11", {"Kluc_Drevina"}, Ciselnik_Dreviny, {"Kluc_Drevina"}, "Ciselnik_Dreviny", JoinKind.LeftOuter),
  #"Expanded Ciselnik_Dreviny" = Table.ExpandTableColumn(#"Merged queries 1", "Ciselnik_Dreviny", {"Nazov_SK", "Nazov_EN", "Skratka_Interne"}, {"Nazov_SK", "Nazov_EN", "Skratka_Interne"}),

  // 4. LOGIKA MODEL A VYROBOK
  #"Added custom 13" = Table.AddColumn(#"Expanded Ciselnik_Dreviny", "Model_Upraveny", each let
    TretieSlovo = try Text.Split([MMFUDS], " "){2} otherwise "",
    Plocha = [Plocha_m2]
  in
    if Plocha <> null and Plocha < 0.85 and TretieSlovo = "BEKANT" then "BEKANT storage" else TretieSlovo),

  #"Added Vyrobok" = Table.AddColumn(#"Added custom 13", "Vyrobok", each let
    ZoznamSlov = Text.Split([MMFUDS], " "),
    DruheSlovo = try ZoznamSlov{1} otherwise "",
    TretieSlovo = try ZoznamSlov{2} otherwise ""
  in
    if Text.EndsWith(DruheSlovo, "0.55") or
       Text.EndsWith(DruheSlovo, "0.35") or
       Text.EndsWith(DruheSlovo, "0.5")
    then TretieSlovo
    else "none"),

  // ---------------------------------------------------------
  // 5. PRIPOJENIE PRODUKTIVITY - (FINÁLNE DOLADENIE)
  // ---------------------------------------------------------

  // A) KOD DREVINY
  // OPRAVA: doplnena vetva pre BUK (predtym spadol na "XX" a nikdy nenasiel produktivitu).
  // Nazov_EN je zaroven osetreny na null.
  #"Add Kod Drevina New" = Table.AddColumn(#"Added Vyrobok", "Kod_Drevina_New", each
    let
      sk = [Skratka_Interne],
      en = if [Nazov_EN] = null then "" else Text.Lower([Nazov_EN])
    in
      if sk = null then "XX"
      else if Text.StartsWith(sk, "JS") then "JS"
      else if Text.StartsWith(sk, "DB") then "DB"
      else if Text.StartsWith(sk, "BK") or Text.Contains(en, "beech") then "BK"
      else if Text.Contains(en, "birch") then "BR"
      else if Text.Contains(en, "walnut") then "OR"
      else if Text.Contains(en, "pine") then "BO"
      else "XX"
  ),

  // B) KOD MODELU - !!! ZMENA: PRESNÉ PRAVIDLÁ PRE HEDEVIKEN A STENSTA !!!
  #"Add Kod Model New" = Table.AddColumn(#"Add Kod Drevina New", "Kod_Model_New", each
    let
      rawM = if [Model_Upraveny] = null then "" else Text.Upper([Model_Upraveny]),
      // OPRAVA: normalizacia aj pre Ä a Å, nielen Ö
      m = Text.Replace(Text.Replace(Text.Replace(rawM, "Ö", "O"), "Ä", "A"), "Å", "A"),
      tech = if [MMITDS] = null then "" else Text.Upper([MMITDS])
    in
      if m = "STOCKHOLM" then "ST"
      else if m = "HEDEVIKEN" then
          // Ak je to Q3, tak je to Standard (16.0), aj ked je tam napisane VE. Inak Dyha (8.0).
          if (Text.Contains(tech, "VE ") or Text.Contains(tech, "Q2V")) and not Text.Contains(tech, "Q3") then "HV" else "HD"
      else if m = "TONSTAD" then "TB"
      else if m = "MITTZON" then "MZ"
      else if m = "BJORKOVIKEN" then "BZ"
      else if m = "BEKANT" or m = "BEKANT STORAGE" then "BE"
      // POZOR: "ST" je tu druhy raz - STRANDTORP ma rovnaky kod ako STOCKHOLM,
      // takze obidva modely tahaju z Nastenky ten isty riadok produktivity.
      // Nechane bez zmeny, kym sa nepotvrdi, aky kod ma STRANDTORP v NastenkaSortProduktivita.
      else if m = "STRANDTORP" then "ST"
      else if m = "STENSTA" then
          // Ak je to Q4/Q5, pouzi kod pre Bjorkoviken (BZ), ktory ma hodnotu 20.0. Inak SE (11.0).
          if Text.Contains(tech, "Q4") or Text.Contains(tech, "Q5") then "BZ" else "SE"
      else if m = "LERHYTTAN" then "LE"
      else if m = "GALANT" then "GT"
      else if m = "HEMNES" then "HN"
      else "XX"
  ),

  // C) KĽÚČ (Trik pre Jaseň HV)
  #"Add Join Key" = Table.AddColumn(#"Add Kod Model New", "Kod_Join", each
    if [Kod_Model_New] = "HV" then "DBHV"
    else [Kod_Drevina_New] & [Kod_Model_New]
  ),

  // MERGE
  #"Merged Nastenka" = Table.NestedJoin(#"Add Join Key", {"Kod_Join"}, Nastenka_Produktivita, {"Kod_Join"}, "Nastenka_Produktivita", JoinKind.LeftOuter),
  #"Expanded Nastenka" = Table.ExpandTableColumn(#"Merged Nastenka", "Nastenka_Produktivita", {"sort_prod_FY26"}, {"sort_prod_FY26"}),

  // ---------------------------------------------------------
  // 6. FINALIZÁCIA A ODSTRÁNENIE DUPLICÍT
  // ---------------------------------------------------------

  #"Changed column type 2" = Table.TransformColumnTypes(#"Expanded Nastenka", {
      {"Model_Upraveny", type text},
      {"Vyrobok", type text},
      {"Kluc_Drevina", type text},
      {"Kod_Drevina_Full", type text},
      {"Cislo_Kvality", Int64.Type},
      {"Final_Cena_FY25", type number},
      {"Final_Cena_FY26", type number},
      {"sort_prod_FY26", type number}
  }, "sk-SK"),

  #"Clean Datum" = Table.ReplaceValue(#"Changed column type 2", "0", null, Replacer.ReplaceValue, {"Datum"}),
  #"Changed column type Datum" = Table.TransformColumnTypes(#"Clean Datum", {{"Datum", type date}}),

  // OPRAVA: cistenie chyb sa muselo presunut PRED Table.Sort.
  // Table.Sort musi hodnoty porovnat, takze chybovu bunku vyhodi von skor,
  // nez ju povodny krok "Replaced errors" (az za Choose columns) stihol nahradit.
  #"Pre-clean errors" = Table.ReplaceErrorValues(#"Changed column type Datum", {
      {"Final_Cena_FY25", null}, {"Final_Cena_FY26", null},
      {"Cena_FY24", null}, {"Cena_FY25", null}, {"Cena_FY26", null},
      {"sort_prod_FY26", null}, {"Datum", null}, {"ODSAPR", null}
  }),

  // Záchrana Sopronu a upratanie duplicit
  // OPRAVA: Table.Buffer AZ ZA sortom - zafixuje poradie riadkov v pamati,
  // takze Table.Distinct spolahlivo nechava riadok s najvyssou cenou.
  // (Bez toho M negarantuje, ze po sorte ostane prave prvy riadok.)
  #"Sorted Rows" = Table.Buffer(Table.Sort(#"Pre-clean errors", {{"Final_Cena_FY26", Order.Descending}})),
  #"Removed Duplicates End" = Table.Distinct(#"Sorted Rows", {"Index_Pre_Deduplikaciu"}),
  #"Removed Index" = Table.RemoveColumns(#"Removed Duplicates End",{"Index_Pre_Deduplikaciu"}),

  #"Choose columns" = Table.SelectColumns(#"Removed Index", {
      "VOFACI", "VOOPNO", "MMDIM1", "MMDIM2", "MMITCL", "VOPRNO", "MDFUDS", "MDITDS",
      "MMSTAT", "MMITDS", "MMFUDS", "VOMFNO", "VOMAQT", "VOSCQT", "VHMAQT", "VOORQT",
      "VHRORN", "ODSAPR", "ODFVDT", "ODLVDT", "MMPRGP",
      "Dlzka_Min", "Dlzka_Max", "Cena_FY24", "Cena_FY25", "Cena_FY26",
      "Final_Cena_FY26", "Final_Cena_FY25", "sort_prod_FY26",
      "Odberatel", "Datum", "Plocha_m2", "Stav_Vyroby", "Rozdiel",
      "Nazov_SK", "Nazov_EN", "Skratka_Interne", "Model_Upraveny", "Vyrobok",
      "Kod_Join", "Kod_Drevina_New", "Kod_Model_New"
  }),

  // Osetrenie chyb (poistka - hlavne cistenie je uz v kroku "Pre-clean errors")
  #"Replaced errors" = Table.ReplaceErrorValues(#"Choose columns", {
      {"Final_Cena_FY25", null}, {"Final_Cena_FY26", null},
      {"Cena_FY26", null}, {"Cena_FY25", null}, {"Cena_FY24", null},
      {"ODSAPR", null}, {"Datum", null}, {"sort_prod_FY26", null}
  }),

  #"Replaced value 2" = Table.ReplaceValue(#"Replaced errors", null, 0, Replacer.ReplaceValue, {
      "VOMAQT", "VOSCQT", "VHMAQT", "VOORQT", "Rozdiel",
      "Final_Cena_FY25", "Final_Cena_FY26", "Cena_FY26", "Cena_FY25", "Cena_FY24",
      "Plocha_m2", "ODSAPR", "sort_prod_FY26"
  }),

  #"Replaced value 3" = Table.ReplaceValue(#"Replaced value 2", null, "", Replacer.ReplaceValue, {
      "MMITCL", "VOPRNO", "MDFUDS", "MDITDS", "MMSTAT", "MMITDS", "MMFUDS",
      "VOMFNO", "VHRORN", "MMPRGP", "Odberatel", "Stav_Vyroby",
      "Nazov_SK", "Nazov_EN", "Skratka_Interne", "Model_Upraveny", "Vyrobok"
  }),

  #"Changed column type" = Table.TransformColumnTypes(#"Replaced value 3", {{"Kod_Join", type text}, {"Kod_Drevina_New", type text}, {"Kod_Model_New", type text}})
in
  #"Changed column type";
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "Ciselnik_Dreviny_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared Ciselnik_Dreviny = let
  Source = #table(
    type table [
      Kluc_Drevina = text,
      Nazov_SK = text,
      Nazov_EN = text,
      Skratka_Interne = text
    ],
    {
      {"JS_HNEDY", "Jaseň hnedý", "Ash brown", "JS hnedy"},
      {"JS_BIELY", "Jaseň biely", "Ash white", "JS biely"},
      {"BREZA_KRAJANA", "Breza krájaná", "Birch sliced", "BRK"},
      {"BREZA_LUPANA", "Breza lúpaná", "Birch rotary", "BRL"},
      {"ORECH", "Orech americký", "Walnut amer", "ORE"},
      {"BUK", "Buk", "Beech", "BK"},
      {"DUB", "Dub", "Oak eur", "DB"},
      {"DUB_V", "Dub V", "Oak V", "DB-V"},
      {"OTHER", "Iné", "Other", "Other"}
    }
  )
in
  Source;
shared Nastenka_Produktivita = let
  Source = Lakehouse.Contents(null),
  Navigation = Source{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],

  // Tvoje ID (nemenil som)
  #"Navigation 1" = Navigation{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  #"Navigation 2" = #"Navigation 1"{[Id = "NastenkaSortProduktivita", ItemKind = "Table"]}[Data],

  // 2. Vyberieme len KÓD (Sortiment_ -> Stlpec A) a PRODUKTIVITU (sort_prod -> Stlpec D)
  #"Choose Columns" = Table.SelectColumns(#"Navigation 2", {"Sortiment_", "sort_prod_FY26"}),
  #"Renamed columns 1" = Table.RenameColumns(#"Choose Columns", {{"sort_prod_FY26", "sort_prod"}}),

  // 3. Premenovanie pre jasnosť
  #"Renamed Columns" = Table.RenameColumns(#"Renamed columns 1",{
      {"Sortiment_", "Kod_Join"},
      {"sort_prod", "sort_prod_FY26"}
  }),

  // 4. Čistenie: Vyhodíme prázdne riadky a nuly
  #"Filtered Rows" = Table.SelectRows(#"Renamed Columns", each ([sort_prod_FY26] <> null and [sort_prod_FY26] <> "NULL" and [sort_prod_FY26] <> "")),

  // 5. Zmena typu na číslo
  #"Changed Type" = Table.TransformColumnTypes(#"Filtered Rows", {{"sort_prod_FY26", type number}}, "sk-SK"),

  // 6. Odstránenie chýb (ak by tam bol text v čísle)
  #"Removed Errors" = Table.RemoveRowsWithErrors(#"Changed Type", {"sort_prod_FY26"}),

  // 7. Úprava Kľúča: Veľké písmená a orezanie medzier (DBST)
  #"Clean Key" = Table.TransformColumns(#"Removed Errors",{
      {"Kod_Join", each Text.Upper(Text.Trim(Text.From(_))), type text}
  }),

  // 8. Odstránenie duplicít
  // Ak je v tabuľke DBST viackrát (napr. kvoli iným stĺpcom), necháme si len jeden riadok, aby sa nám nenásobili dáta.
  #"Removed Duplicates" = Table.Distinct(#"Clean Key", {"Kod_Join"})
in
  #"Removed Duplicates";
shared DyhaRaw = let
    Source = Excel.Workbook(
        File.Contents("\\10.196.244.10\windata\06_Obchod\02_NAKUP\01_EVIDENCIA\PRÍJEM DYHY.xlsx"),
        null,
        true
    ),
    Navigation = Source{[Item = "List1", Kind = "Sheet"]}[Data],
    RemovedTopRows = Table.Skip(Navigation, 5),
    PromotedHeaders = Table.PromoteHeaders(RemovedTopRows, [PromoteAllScalars = true]),
  #"Filtered rows" = Table.SelectRows(PromotedHeaders, each ([InvoicingDate] <> null and [InvoicingDate] <> "") and ([Dátum výdaja] <> null and [Dátum výdaja] <> "")),
    SelectedColumns = Table.SelectColumns(
        #"Filtered rows",
        {
            "Movex NR.",
            "Drevina",
            "Dátum výdaja",
            "PURS",
            "Dátum výdaja reklamácie do výroby",
            "Výdaj reklamácie PURCLAIM=>PURS m2",
            "Dátum výdaja reklamácie do výroby1",
            "Výdaj reklamácie PURCLAIM=>PURS m21",
            "Dátum výdaja reklamácie do výroby2",
            "Výdaj reklamácie PURCLAIM=>PURS m22"
        },
        MissingField.UseNull
    ),
    ChangedType = Table.TransformColumnTypes(
        SelectedColumns,
        {
            {"Movex NR.", type text},
            {"Drevina", type text},
            {"Dátum výdaja", type date},
            {"PURS", type number},
            {"Dátum výdaja reklamácie do výroby", type date},
            {"Výdaj reklamácie PURCLAIM=>PURS m2", type number},
            {"Dátum výdaja reklamácie do výroby1", type date},
            {"Výdaj reklamácie PURCLAIM=>PURS m21", type number},
            {"Dátum výdaja reklamácie do výroby2", type date},
            {"Výdaj reklamácie PURCLAIM=>PURS m22", type number}
        }
    )
in
    ChangedType;
shared VydajDyhy = let
    Source = DyhaRaw,
    Selected = Table.SelectColumns(Source, {"Movex NR.", "Drevina", "Dátum výdaja", "PURS"}),
    Filtered = Table.SelectRows(Selected, each [Dátum výdaja] <> null),
    Renamed = Table.RenameColumns(Filtered, {
        {"Dátum výdaja", "Datum"},
        {"PURS", "Mnozstvo"}
    }),
    AddedTyp = Table.AddColumn(Renamed, "Typ", each "Výdaj", type text)
in
    AddedTyp;
shared VrateneDoVyroby1 = let
    Source = DyhaRaw,
    Selected = Table.SelectColumns(Source, {"Movex NR.", "Drevina", "Dátum výdaja reklamácie do výroby", "Výdaj reklamácie PURCLAIM=>PURS m2"}),
    Filtered = Table.SelectRows(Selected, each [Dátum výdaja reklamácie do výroby] <> null),
    Renamed = Table.RenameColumns(Filtered, {
        {"Dátum výdaja reklamácie do výroby", "Datum"},
        {"Výdaj reklamácie PURCLAIM=>PURS m2", "Mnozstvo"}
    }),
    AddedTyp = Table.AddColumn(Renamed, "Typ", each "Vrátené 1", type text)
in
    AddedTyp;
shared VrateneDoVyroby2 = let
    Source = DyhaRaw,
    Selected = Table.SelectColumns(Source, {"Movex NR.", "Drevina", "Dátum výdaja reklamácie do výroby1", "Výdaj reklamácie PURCLAIM=>PURS m21"}),
    Filtered = Table.SelectRows(Selected, each [Dátum výdaja reklamácie do výroby1] <> null),
    Renamed = Table.RenameColumns(Filtered, {
        {"Dátum výdaja reklamácie do výroby1", "Datum"},
        {"Výdaj reklamácie PURCLAIM=>PURS m21", "Mnozstvo"}
    }),
    AddedTyp = Table.AddColumn(Renamed, "Typ", each "Vrátené 2", type text)
in
    AddedTyp;
shared VrateneDoVyroby3 = let
    Source = DyhaRaw,
    Selected = Table.SelectColumns(Source, {"Movex NR.", "Drevina", "Dátum výdaja reklamácie do výroby2", "Výdaj reklamácie PURCLAIM=>PURS m22"}),
    Filtered = Table.SelectRows(Selected, each [Dátum výdaja reklamácie do výroby2] <> null),
    Renamed = Table.RenameColumns(Filtered, {
        {"Dátum výdaja reklamácie do výroby2", "Datum"},
        {"Výdaj reklamácie PURCLAIM=>PURS m22", "Mnozstvo"}
    }),
    AddedTyp = Table.AddColumn(Renamed, "Typ", each "Vrátené 3", type text)
in
    AddedTyp;
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "DyhaFinal_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared DyhaFinal = let
    Source = Table.Combine({VydajDyhy, VrateneDoVyroby1, VrateneDoVyroby2, VrateneDoVyroby3}),

    AddedDen = Table.AddColumn(Source, "Den_", each Date.Day([Datum]), Int64.Type),
    AddedRok = Table.AddColumn(AddedDen, "ROK_", each Date.Year([Datum]), Int64.Type),
    // OPRAVA: bez druheho parametra pocita M tyzden od nedele -> cisla tyzdnov boli posunute.
    AddedTyzden = Table.AddColumn(AddedRok, "Tyzden_", each Date.WeekOfYear([Datum], Day.Monday), Int64.Type),

    AddedMesiac = Table.AddColumn(AddedTyzden, "Mesiac_", each
        Text.PadStart(Text.From(Date.Month([Datum])), 2, "0")
        & "_"
        & {"Január","Február","Marec","Apríl","Máj","Jún","Júl","August","September","Október","November","December"}{Date.Month([Datum])-1}
        & "_",
        type text
    ),

    AddedFY = Table.AddColumn(AddedMesiac, "FY_", each
        if Date.Month([Datum]) >= 9
        then "FY" & Text.End(Text.From(Date.Year([Datum]) + 1), 2)
        else "FY" & Text.End(Text.From(Date.Year([Datum])), 2),
        type text
    ),

    RenamedDrevina = Table.RenameColumns(AddedFY, {{"Drevina", "Drevina_"}})
in
    RenamedDrevina;
shared Ciselnik_Dreviny_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "40a03b51-8bc8-4154-880a-b31f58231c00"]}[Data],
  TableNavigation = Navigation_2{[Id = "Ciselnik_Dreviny", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
shared Cennik_Majcichov_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "40a03b51-8bc8-4154-880a-b31f58231c00"]}[Data],
  TableNavigation = Navigation_2{[Id = "Cennik_Majcichov_merge", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
shared #"SPA MAJ_523_VyrobneObjednavky_DataDestination" = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "40a03b51-8bc8-4154-880a-b31f58231c00"]}[Data],
  TableNavigation = Navigation_2{[Id = "MAJ_523_VyrobneObjednavky_cennik", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
// NOVE: jedno miesto, kde je definovana cesta k zositu rozmery.xlsx.
// Pri zmene servera/priecinka sa meni len tu, nie v dvoch dotazoch.
shared RozmeryRaw = let
  Source = Excel.Workbook(File.Contents("\\10.196.244.10\windata\06_Obchod\01_EXPEDICIA\Ekedalen\preskladnené výrobky z TT\rozmery.xlsx"), null, true)
in
  Source;
// NOVE: jedno miesto pre zosit Evidencia HV z TT.xlsx vratane dvojiteho promote headers,
// ktory bol predtym duplikovany v dotazoch prijem aj vyvoz.
shared EvidenciaHVRaw = let
  Source = Excel.Workbook(File.Contents("\\10.196.244.10\windata\06_Obchod\01_EXPEDICIA\Ekedalen\preskladnené výrobky z TT\Evidencia HV z TT.xlsx"), null, true),
  #"Navigation 1" = Source{[Item = "evidencia HV", Kind = "Sheet"]}[Data],
  #"Promoted headers" = Table.PromoteHeaders(#"Navigation 1", [PromoteAllScalars = true]),
  #"Promoted headers 1" = Table.PromoteHeaders(#"Promoted headers", [PromoteAllScalars = true])
in
  #"Promoted headers 1";
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "rozmery_koji_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared rozmery_koji = let
  Source = RozmeryRaw,

  #"Navigation 1" = Source{[Item = "rozmery_koji", Kind = "Sheet"]}[Data],
  #"Promoted headers" = Table.PromoteHeaders(#"Navigation 1", [PromoteAllScalars = true]),

  // Premenovanie a zaistenie, že stĺpce sú vnímané ako text pre náhradu znakov
  #"Renamed columns" = Table.RenameColumns(#"Promoted headers", {{"kója", "Location"}, {"šírka", "šírka_koje_xls"}, {"dĺžka", "dĺžka_koje_xls"}, {"výška", "výška_koje_xls"}, {"m2", "m2_koje_xls"}}),
  #"Convert to Text" = Table.TransformColumnTypes(#"Renamed columns", {{"šírka_koje_xls", type text}, {"dĺžka_koje_xls", type text}, {"výška_koje_xls", type text}, {"m2_koje_xls", type text}}),

  // 1. Pridanie stĺpca Blokovane priamo v Dataflowe
  // OPRAVA: Text.From(null) -> null -> Text.Contains(null, ...) -> null -> "if null" zhodilo dotaz.
  // Prazdna bunka v stlpci dlzka je teraz osetrena skratovym vyhodnotenim.
  #"Added Blokovane" = Table.AddColumn(#"Convert to Text", "Blokovane", each
      if [dĺžka_koje_xls] <> null and Text.Contains(Text.Lower(Text.From([dĺžka_koje_xls])), "blokova")
      then "blokovane" else "neblokovane", type text),

  // 2. Nahradenie "blokované" nulou vo všetkých relevantných stĺpcoch
  #"Replace Blokovane" = Table.ReplaceValue(#"Added Blokovane", "blokované", "0", Replacer.ReplaceText, {"šírka_koje_xls", "dĺžka_koje_xls", "výška_koje_xls", "m2_koje_xls"}),

  // 3. OPRAVA ČIAROK NA BODKY - toto odstráni [Error] v m2_koje_xls
  #"Fix Commas" = Table.ReplaceValue(#"Replace Blokovane", ",", ".", Replacer.ReplaceText, {"šírka_koje_xls", "dĺžka_koje_xls", "výška_koje_xls", "m2_koje_xls"}),

  // 4. Finálna zmena na číselné typy
  #"Final Types" = Table.TransformColumnTypes(#"Fix Commas", {
      {"šírka_koje_xls", type number},
      {"dĺžka_koje_xls", type number},
      {"výška_koje_xls", type number},
      {"m2_koje_xls", type number},
      {"status", Int64.Type}
  }),

  // 5. Poistka: Nahradenie akýchkoľvek zostávajúcich chýb nulou
  #"Clean Remaining Errors" = Table.ReplaceErrorValues(#"Final Types", {{"šírka_koje_xls", 0}, {"dĺžka_koje_xls", 0}, {"výška_koje_xls", 0}, {"m2_koje_xls", 0}}),
  #"Changed column type" = Table.TransformColumnTypes(#"Clean Remaining Errors", {{"Location", type text}, {"poznamka", type text}}),
  #"Removed columns" = Table.RemoveColumns(#"Changed column type", {"m2 zona"})
in
  #"Removed columns";
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "rozmery_paliet_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared rozmery_paliet = let
  Source = RozmeryRaw,
  #"Navigation 1" = Source{[Item = "rozmery_paliet", Kind = "Sheet"]}[Data],
  #"Promoted headers" = Table.PromoteHeaders(#"Navigation 1", [PromoteAllScalars = true]),

  // 1. Najprv zmeníme typ na Text (Excel už nuly zmazal, ale potrebujeme textový formát pre ďalší krok)
  #"Changed column type" = Table.TransformColumnTypes(#"Promoted headers", {{"položka", type text}, {"popis1", type text}, {"popis2", type text}, {"dlžka palety", Int64.Type}, {"šírka palety", Int64.Type}, {"výška palety", Int64.Type}, {"Column9", type text}, {"Column14", Int64.Type}}),

  // 2. NOVÝ KROK: Doplníme nuly zľava, aby mala položka vždy 13 znakov
  // OPRAVA: Text.PadStart(null, 13, "0") vracia null a spadol by nasledujuci join na Product.
  #"Doplnenie_Nul" = Table.TransformColumns(#"Changed column type", {{"položka", each if _ = null then null else Text.PadStart(_, 13, "0"), type text}}),

  // 3. Premenovanie stĺpcov (teraz už pracujeme s opraveným stĺpcom z kroku vyššie)
  #"Renamed columns" = Table.RenameColumns(#"Doplnenie_Nul", {{"položka", "Product"}, {"dlžka palety", "dlžka_palety_xls"}, {"šírka palety", "šírka_palety_xls"}, {"výška palety", "výška_palety_xls"}}),

  #"Choose columns" = Table.SelectColumns(#"Renamed columns", {"Product", "popis1", "popis2", "dlžka_palety_xls", "šírka_palety_xls", "výška_palety_xls"})
in
  #"Choose columns";
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "evidencia_HV_prijem_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared evidencia_HV_prijem = let
  Source = EvidenciaHVRaw,
  #"Choose columns" = Table.SelectColumns(Source, {"dátum príjmu", "TDN-MAJ", "TDN-TT", "Dodávateľ", "Dopravca", "ŠPZ", "vodič", "plomba č.", "artikel", "kontajner č.", "počet ks", "popis mvx 1", "popis mvx 2"}),
  #"Renamed columns" = Table.RenameColumns(#"Choose columns", {{"Dopravca", "Dopravca_dovoz"}, {"ŠPZ", "ŠPZ_dovoz"}, {"plomba č.", "plomba_dovoz"}, {"artikel", "Produkt"}, {"kontajner č.", "kontajner_dovoz"}, {"počet ks", "počet_vyrobkov_v_palete_dovoz"}}),
  #"Changed column type" = Table.TransformColumnTypes(#"Renamed columns", {{"dátum príjmu", type date}, {"TDN-MAJ", type text}, {"TDN-TT", type text}, {"Dodávateľ", type text}, {"Dopravca_dovoz", type text}, {"ŠPZ_dovoz", type text}, {"vodič", type text}, {"plomba_dovoz", type text}, {"Produkt", type text}, {"kontajner_dovoz", type text}, {"počet_vyrobkov_v_palete_dovoz", Int64.Type}, {"popis mvx 1", type text}, {"popis mvx 2", type text}})
in
  #"Changed column type";
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "evidencia_HV_vyvoz_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared evidencia_HV_vyvoz = let
  Source = EvidenciaHVRaw,
  #"Choose columns" = Table.SelectColumns(Source, {"dátum vývozu", "TDN-MAJ_1", "plomba č.1", "Odberateľ", "Dopravca_2", "ŠPZ_3", "vodič_4", "artikel_5", "kontajner č._6", "počet ks_7", "popis mvx 1_8", "popis mvx 2_9"}),
  #"Renamed columns" = Table.RenameColumns(#"Choose columns", {{"TDN-MAJ_1", "TDN_vyvozu"}, {"plomba č.1", "plomba_vyvoz"}, {"Dopravca_2", "Dopravca_vyvoz"}, {"ŠPZ_3", "SPZ_vyvoz"}, {"vodič_4", "vodic_vyvoz"}, {"artikel_5", "Produkt"}, {"kontajner č._6", "kontajner_vyvoz"}, {"počet ks_7", "počet_vyrobkov_v_palete_vyvoz"}}),
  #"Changed column type" = Table.TransformColumnTypes(#"Renamed columns", {{"dátum vývozu", type date}, {"TDN_vyvozu", type text}, {"plomba_vyvoz", type text}, {"Odberateľ", type text}, {"Dopravca_vyvoz", type text}, {"SPZ_vyvoz", type text}, {"vodic_vyvoz", type text}, {"Produkt", type text}, {"kontajner_vyvoz", type text}, {"počet_vyrobkov_v_palete_vyvoz", Int64.Type}, {"popis mvx 1_8", type text}, {"popis mvx 2_9", type text}})
in
  #"Changed column type";
shared rozmery_paliet_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  TableNavigation = Navigation_2{[Id = "rozmery_paliet", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
shared evidencia_HV_vyvoz_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  TableNavigation = Navigation_2{[Id = "evidencia_HV_vyvoz", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
shared evidencia_HV_prijem_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  TableNavigation = Navigation_2{[Id = "evidencia_HV_prijem", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
shared rozmery_koji_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  TableNavigation = Navigation_2{[Id = "rozmery_koji_new", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
shared DyhaFinal_DataDestination = let
  Pattern = Lakehouse.Contents([CreateNavigationProperties = false, EnableFolding = false, HierarchicalNavigation = null, PreserveOrder = null]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  TableNavigation = Navigation_2{[Id = "DyhaFinal", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
