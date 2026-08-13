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
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "SPA MAJ_523_VyrobneObjednavky_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared SPA_MAJ_523_VyrobneObjednavky = let
  Source = Lakehouse.Contents(null),
  Navigation = Source{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  #"Navigation 1" = Navigation{[lakehouseId = "a31bc90d-0406-46ab-b4c5-88c54250fdd9"]}[Data],
  #"Navigation 2" = #"Navigation 1"{[Id = "SPA.MAJ_523_VyrobneObjednavky", ItemKind = "View"]}[Data],

  // 1. PRIDANIE INDEXU (proti duplicitam)
  #"Added Index" = Table.AddIndexColumn(#"Navigation 2", "Index_Pre_Deduplikaciu", 0, 1, Int64.Type),

  // 2. STARA LOGIKA - parsovanie kodov z popisov
  #"Added custom" = Table.AddColumn(#"Added Index", "Kod_Model_Old", each 
    try Text.Start(Text.Split([MMITDS], " "){3}, 2) otherwise null, type nullable text),

  #"Added custom 1" = Table.AddColumn(#"Added custom", "Kod_Drevina_Old", each 
    try Text.Start(Text.Split([MDITDS], " "){2}, 2) otherwise null, type nullable text),

  #"Added custom 2" = Table.AddColumn(#"Added custom 1", "Kod_Kvalita", each 
    try Text.Start(Text.Split([MMITDS], " "){4}, 4) otherwise null, type nullable text),

  // 3. PREPOJENIE NA CENNIK
  #"Merged queries" = Table.NestedJoin(#"Added custom 2", 
    {"MMPRGP", "Kod_Model_Old", "Kod_Drevina_Old", "Kod_Kvalita"}, 
    Cennik_Majcichov, 
    {"MMPRGP", "Kod_Model", "Kod_Drevina", "Kod_Kvalita"}, 
    "Cennik_Majcichov", JoinKind.LeftOuter),

  #"Expanded Cennik_Majcichov" = Table.ExpandTableColumn(#"Merged queries", "Cennik_Majcichov", 
      {"Dlzka_Min", "Dlzka_Max", "Cena_FY24", "Cena_FY25", "Cena_FY26"}, 
      {"Dlzka_Min", "Dlzka_Max", "Cena_FY24", "Cena_FY25", "Cena_FY26"}),

  // 4. VYPOCET CIEN - osetrene vsetky null vstupy
  #"Added custom 3" = Table.AddColumn(#"Expanded Cennik_Majcichov", "Final_Cena_FY26", each 
    if [Dlzka_Min] <> null and [Dlzka_Max] <> null and [MMDIM1] <> null
       and [MMDIM1] >= [Dlzka_Min] and [MMDIM1] <= [Dlzka_Max] 
    then [Cena_FY26] else null, type nullable number),

  #"Added custom 4" = Table.AddColumn(#"Added custom 3", "Final_Cena_FY25", each 
    if [Dlzka_Min] <> null and [Dlzka_Max] <> null and [MMDIM1] <> null
       and [MMDIM1] >= [Dlzka_Min] and [MMDIM1] <= [Dlzka_Max] 
    then [Cena_FY25] else null, type nullable number),

  // 5. LOGIKA PRE DREVINY
  // POZOR: try/otherwise nechyta null - Text.Middle(null,..) vracia null bez chyby.
  // Preto sa null osetruje explicitne.
  #"Added custom 9" = Table.AddColumn(#"Added custom 4", "Cislo_Kvality", each 
    let 
      v = try Number.From(Text.Middle(if [Kod_Kvalita] = null then "" else [Kod_Kvalita], 1, 1)) otherwise null
    in 
      if v = null then 0 else v, Int64.Type),

  #"Added custom 10" = Table.AddColumn(#"Added custom 9", "Kod_Drevina_Full", each 
    try Text.Start(Text.Split([MMFUDS], " "){2}, 2) otherwise "", type text),

  #"Added custom 11" = Table.AddColumn(#"Added custom 10", "Kluc_Drevina", each 
    let 
      kv = if [Cislo_Kvality] = null then 0 else [Cislo_Kvality],
      kval = if [Kod_Kvalita] = null then "" else [Kod_Kvalita]
    in
      if [MMPRGP] = "P31" or [MMPRGP] = "P28" then
        if kv > 2 then "JS_HNEDY" else "JS_BIELY"
      else if [MMPRGP] = "P27" then
        if kv > 4 then "BREZA_KRAJANA" else "BREZA_LUPANA"
      else if [MMPRGP] = "P25" then "ORECH"
      else if [MMPRGP] = "P26" then "BUK"
      else if [MMPRGP] = "P29" then
        if [Kod_Drevina_Full] = "HE" and Text.Contains(kval, "V") then "DUB_V" else "DUB"
      else "OTHER", type text),

  #"Merged queries 1" = Table.NestedJoin(#"Added custom 11", {"Kluc_Drevina"}, 
    Ciselnik_Dreviny, {"Kluc_Drevina"}, "Ciselnik_Dreviny", JoinKind.LeftOuter),

  #"Expanded Ciselnik_Dreviny" = Table.ExpandTableColumn(#"Merged queries 1", "Ciselnik_Dreviny", 
    {"Nazov_SK", "Nazov_EN", "Skratka_Interne"}, 
    {"Nazov_SK", "Nazov_EN", "Skratka_Interne"}),

  // 6. LOGIKA MODEL A VYROBOK
  #"Added custom 13" = Table.AddColumn(#"Expanded Ciselnik_Dreviny", "Model_Upraveny", each 
    let
      TretieSlovo = try Text.Split([MMFUDS], " "){2} otherwise "",
      Plocha = try Number.From([Plocha_m2]) otherwise null
    in
      if Plocha <> null and Plocha < 0.85 and TretieSlovo = "BEKANT" 
      then "BEKANT storage" else TretieSlovo, type text),

  #"Added Vyrobok" = Table.AddColumn(#"Added custom 13", "Vyrobok", each 
    let
      ZoznamSlov = try Text.Split([MMFUDS], " ") otherwise {},
      DruheSlovo = try ZoznamSlov{1} otherwise "",
      TretieSlovo = try ZoznamSlov{2} otherwise ""
    in
      if Text.EndsWith(DruheSlovo, "0.55") or 
         Text.EndsWith(DruheSlovo, "0.35") or 
         Text.EndsWith(DruheSlovo, "0.5") 
      then TretieSlovo 
      else "none", type text),

  // 7. PRIPOJENIE PRODUKTIVITY
  // A) KOD DREVINY
  #"Add Kod Drevina New" = Table.AddColumn(#"Added Vyrobok", "Kod_Drevina_New", each 
    let 
      en = if [Nazov_EN] = null then "" else Text.Lower([Nazov_EN]),
      sk = [Skratka_Interne]
    in
      if sk = null then "XX" 
      else if Text.StartsWith(sk, "JS") then "JS"
      else if Text.StartsWith(sk, "DB") then "DB"
      else if Text.Contains(en, "birch") then "BR"
      else if Text.Contains(en, "walnut") then "OR"
      else if Text.Contains(en, "pine") then "BO"
      else "XX", type text),

  // B) KOD MODELU - presne pravidla pre HEDEVIKEN a STENSTA
  #"Add Kod Model New" = Table.AddColumn(#"Add Kod Drevina New", "Kod_Model_New", each 
    let 
      rawM = if [Model_Upraveny] = null then "" else Text.Upper([Model_Upraveny]),
      // OPRAVA: normalizacia aj pre Ä a Å, nielen Ö (svedske nazvy modelov)
      m = Text.Replace(Text.Replace(Text.Replace(rawM, "Ö", "O"), "Ä", "A"), "Å", "A"),
      tech = if [MMITDS] = null then "" else Text.Upper([MMITDS])
    in
      if m = "STOCKHOLM" then "ST"
      else if m = "HEDEVIKEN" then 
          // Q3 = Standard (16.0), aj ked je tam VE. Inak Dyha (8.0).
          if (Text.Contains(tech, "VE ") or Text.Contains(tech, "Q2V")) and not Text.Contains(tech, "Q3") 
          then "HV" else "HD"
      else if m = "TONSTAD" then "TB"
      else if m = "MITTZON" then "MZ"
      else if m = "BJORKOVIKEN" then "BZ" 
      else if m = "BEKANT" or m = "BEKANT STORAGE" then "BE" 
      else if m = "STRANDTORP" then "ST"
      else if m = "STENSTA" then 
          // Q4/Q5 = kod pre Bjorkoviken (BZ, hodnota 20.0). Inak SE (11.0).
          if Text.Contains(tech, "Q4") or Text.Contains(tech, "Q5") then "BZ" else "SE"
      else if m = "LERHYTTAN" then "LE"
      else if m = "GALANT" then "GT"
      else if m = "HEMNES" then "HN"
      else "XX", type text),

  // C) KLUC (trik pre Jasen HV)
  #"Add Join Key" = Table.AddColumn(#"Add Kod Model New", "Kod_Join", each 
    let
      kd = if [Kod_Drevina_New] = null then "XX" else [Kod_Drevina_New],
      km = if [Kod_Model_New] = null then "XX" else [Kod_Model_New]
    in
      if km = "HV" then "DBHV" else kd & km, type text),

  #"Merged Nastenka" = Table.NestedJoin(#"Add Join Key", {"Kod_Join"}, 
    Nastenka_Produktivita, {"Kod_Join"}, "Nastenka_Produktivita", JoinKind.LeftOuter),

  #"Expanded Nastenka" = Table.ExpandTableColumn(#"Merged Nastenka", "Nastenka_Produktivita", 
    {"sort_prod_FY26"}, {"sort_prod_FY26"}),

  // 8. FINALIZACIA A ODSTRANENIE DUPLICIT
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

  // OPRAVA: cistenie chybovych buniek muselo ist PRED Table.Sort.
  // Sort musi hodnoty porovnat, takze chybovu bunku (napr. z prevodu typu
  // v kroku "Changed column type 2") vyhodi von skor, nez ju stihne
  // nahradit krok "Replaced errors", ktory je az za "Choose columns".
  // Toto NIE JE zmena logiky deduplikacie - Sort ani Distinct sa nemenia.
  #"Pre-clean errors" = Table.ReplaceErrorValues(#"Changed column type Datum", {
      {"Final_Cena_FY25", null}, {"Final_Cena_FY26", null},
      {"Cena_FY24", null}, {"Cena_FY25", null}, {"Cena_FY26", null},
      {"sort_prod_FY26", null}, {"Datum", null}, {"ODSAPR", null}
  }),

  // Zachrana Sopronu a upratanie duplicit
  #"Sorted Rows" = Table.Sort(#"Pre-clean errors", {{"Final_Cena_FY26", Order.Descending}}),
  #"Removed Duplicates End" = Table.Distinct(#"Sorted Rows", {"Index_Pre_Deduplikaciu"}),
  #"Removed Index" = Table.RemoveColumns(#"Removed Duplicates End", {"Index_Pre_Deduplikaciu"}),

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

  // 9. OSETRENIE CHYB A NULL HODNOT
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

  #"Changed column type" = Table.TransformColumnTypes(#"Replaced value 3", {
      {"Kod_Join", type text}, {"Kod_Drevina_New", type text}, {"Kod_Model_New", type text}
  })
in
  #"Changed column type";
shared Cennik_Majcichov_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "40a03b51-8bc8-4154-880a-b31f58231c00"]}[Data],
  TableNavigation = Navigation_2{[Id = "Cennik_Majcichov_merge", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
shared Ciselnik_Dreviny_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "40a03b51-8bc8-4154-880a-b31f58231c00"]}[Data],
  TableNavigation = Navigation_2{[Id = "Ciselnik_Dreviny", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
shared #"SPA MAJ_523_VyrobneObjednavky_DataDestination" = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "40a03b51-8bc8-4154-880a-b31f58231c00"]}[Data],
  TableNavigation = Navigation_2{[Id = "MAJ_523_VyrobneObjednavky_cennik", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
