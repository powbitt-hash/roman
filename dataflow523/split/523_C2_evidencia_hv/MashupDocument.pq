[StagingDefinition = [Kind = "FastCopy"]]
section Section1;
// NOVE: jedno miesto pre zosit Evidencia HV z TT.xlsx vratane dvojiteho
// PromoteHeaders, ktory bol predtym duplikovany v dotazoch prijem aj vyvoz.
shared EvidenciaHVRaw = let
  Source = Excel.Workbook(File.Contents("\\10.196.244.10\windata\06_Obchod\01_EXPEDICIA\Ekedalen\preskladnené výrobky z TT\Evidencia HV z TT.xlsx"), null, true),
  #"Navigation 1" = Source{[Item = "evidencia HV", Kind = "Sheet"]}[Data],
  #"Promoted headers" = Table.PromoteHeaders(#"Navigation 1", [PromoteAllScalars = true]),
  #"Promoted headers 1" = Table.PromoteHeaders(#"Promoted headers", [PromoteAllScalars = true])
in
  #"Promoted headers 1";
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
shared evidencia_HV_prijem_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  TableNavigation = Navigation_2{[Id = "evidencia_HV_prijem", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
shared evidencia_HV_vyvoz_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = null, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "c53e181c-8c7c-4981-91a3-e5fe14d45961"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "a0eb9dbf-4d7a-40db-95b7-a539de0e7530"]}[Data],
  TableNavigation = Navigation_2{[Id = "evidencia_HV_vyvoz", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
