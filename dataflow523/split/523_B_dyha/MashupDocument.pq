[StagingDefinition = [Kind = "FastCopy"]]
section Section1;
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
    AddedTyzden = Table.AddColumn(AddedRok, "Tyzden_", each Date.WeekOfYear([Datum]), Int64.Type),
    
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
shared DyhaFinal_DataDestination = let
  Pattern = Lakehouse.Contents([CreateNavigationProperties = false, EnableFolding = false, HierarchicalNavigation = null, PreserveOrder = null]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  TableNavigation = Navigation_2{[Id = "DyhaFinal", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
