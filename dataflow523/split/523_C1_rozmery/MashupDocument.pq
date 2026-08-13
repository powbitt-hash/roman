[StagingDefinition = [Kind = "FastCopy"]]
section Section1;
// NOVE: jedno miesto, kde je definovana cesta k zositu rozmery.xlsx.
// Pri zmene servera alebo priecinka sa meni len tu, nie v dvoch dotazoch.
// Bez destinacie a bez stagingu.
shared RozmeryRaw = let
  Source = Excel.Workbook(File.Contents("\\10.196.244.10\windata\06_Obchod\01_EXPEDICIA\Ekedalen\preskladnené výrobky z TT\rozmery.xlsx"), null, true)
in
  Source;
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "rozmery_koji_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared rozmery_koji = let
  Source = RozmeryRaw,

  #"Navigation 1" = Source{[Item = "rozmery_koji", Kind = "Sheet"]}[Data],
  #"Promoted headers" = Table.PromoteHeaders(#"Navigation 1", [PromoteAllScalars = true]),
  
  // Premenovanie a zaistenie, že stĺpce sú vnímané ako text pre náhradu znakov
  #"Renamed columns" = Table.RenameColumns(#"Promoted headers", {{"kója", "Location"}, {"šírka", "šírka_koje_xls"}, {"dĺžka", "dĺžka_koje_xls"}, {"výška", "výška_koje_xls"}, {"m2", "m2_koje_xls"}}),
  #"Convert to Text" = Table.TransformColumnTypes(#"Renamed columns", {{"šírka_koje_xls", type text}, {"dĺžka_koje_xls", type text}, {"výška_koje_xls", type text}, {"m2_koje_xls", type text}}),

  // 1. Pridanie stĺpca Blokovane priamo v Dataflowe
  // OPRAVA: Text.From(null) -> null -> Text.Contains(null, ...) -> null -> "if null"
  // zhodilo cely dotaz (rovnaka chyba ako ErrorCode 10277 v objednavkach).
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
  // OPRAVA: Text.PadStart(null, 13, "0") vracia null, cim by prazdny riadok
  // rozbil neskorsi join na Product.
  #"Doplnenie_Nul" = Table.TransformColumns(#"Changed column type", {{"položka", each if _ = null then null else Text.PadStart(_, 13, "0"), type text}}),

  // 3. Premenovanie stĺpcov (teraz už pracujeme s opraveným stĺpcom z kroku vyššie)
  #"Renamed columns" = Table.RenameColumns(#"Doplnenie_Nul", {{"položka", "Product"}, {"dlžka palety", "dlžka_palety_xls"}, {"šírka palety", "šírka_palety_xls"}, {"výška palety", "výška_palety_xls"}}),
  
  #"Choose columns" = Table.SelectColumns(#"Renamed columns", {"Product", "popis1", "popis2", "dlžka_palety_xls", "šírka_palety_xls", "výška_palety_xls"})
in
  #"Choose columns";
shared rozmery_koji_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  TableNavigation = Navigation_2{[Id = "rozmery_koji_new", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
shared rozmery_paliet_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  TableNavigation = Navigation_2{[Id = "rozmery_paliet", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
