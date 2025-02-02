(* ::Section::Closed:: *)
(*Package Header*)
BeginPackage[ "Wolfram`Chatbook`Sandbox`" ];

(* cSpell: ignore noinit pacletreadonly playerpass sntx *)

(* :!CodeAnalysis::BeginBlock:: *)
(* :!CodeAnalysis::Disable::SuspiciousSessionSymbol:: *)

`fancyResultQ;
`sandboxEvaluate;
`sandboxFormatter;
`simpleResultQ;
`$sandboxKernelCommandLine;

Begin[ "`Private`" ];

Needs[ "Wolfram`Chatbook`"            ];
Needs[ "Wolfram`Chatbook`Common`"     ];
Needs[ "Wolfram`Chatbook`Formatting`" ];
Needs[ "Wolfram`Chatbook`Tools`"      ];
Needs[ "Wolfram`Chatbook`Utils`"      ];

(* ::**************************************************************************************************************:: *)
(* ::Section::Closed:: *)
(*Configuration*)
$SandboxKernel             = None;
$sandboxPingTimeout       := toolOptionValue[ "WolframLanguageEvaluator", "PingTimeConstraint"       ];
$sandboxEvaluationTimeout := toolOptionValue[ "WolframLanguageEvaluator", "EvaluationTimeConstraint" ];
$includeDefinitions       := toolOptionValue[ "WolframLanguageEvaluator", "IncludeDefinitions"       ];
$cloudEvaluatorLocation    = "/Chatbook/Tools/WolframLanguageEvaluator/Evaluate";
$cloudLineNumber           = 1;
$cloudSession              = None;

(* Tests for expressions that lose their initialized status when sending over a link: *)
$initializationTests = HoldComplete[
    AudioQ,
    BoundaryMeshRegionQ,
    DateObjectQ,
    GraphQ,
    MeshRegionQ,
    SparseArrayQ,
    TreeQ,
    VideoQ,
    Function[ Null, MatchQ[ Unevaluated @ #, _Rational ] && AtomQ @ Unevaluated @ #, HoldFirst ],
    Function[ Null, MatchQ[ Unevaluated @ #, _Dataset ] && System`Private`HoldNoEntryQ @ #, HoldFirst ]
];


$sandboxKernelCommandLine := StringRiffle @ {
    ToString[
        If[ $OperatingSystem === "Windows",
            FileNameJoin @ { $InstallationDirectory, "WolframKernel" },
            First @ $CommandLine
        ],
        InputForm
    ],
    "-wstp",
    "-noicon",
    "-noinit",
    "-pacletreadonly",
    "-run",
    "ChatbookSandbox" <> ToString @ $ProcessID
};

$$outputForm := $$outputForm = Alternatives @@ $OutputForms;

(* ::**************************************************************************************************************:: *)
(* ::Section::Closed:: *)
(*Kernel Management*)

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*Get Kernel*)

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*getSandboxKernel*)
getSandboxKernel // beginDefinition;
getSandboxKernel[ ] := getSandboxKernel @ Select[ Links[ ], sandboxKernelQ ];
getSandboxKernel[ { other__LinkObject, kernel_ } ] := (Scan[ LinkClose, { other } ]; getSandboxKernel @ { kernel });
getSandboxKernel[ { kernel_LinkObject } ] := checkSandboxKernel @ kernel;
getSandboxKernel[ { } ] := startSandboxKernel[ ];
getSandboxKernel // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*Kernel Status*)

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*sandboxKernelQ*)
sandboxKernelQ[ LinkObject[ cmd_String, ___ ] ] := StringContainsQ[ cmd, "ChatbookSandbox" <> ToString @ $ProcessID ];
sandboxKernelQ[ ___ ] := False;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*checkSandboxKernel*)
checkSandboxKernel // beginDefinition;
checkSandboxKernel[ kernel_LinkObject ] /; IntegerQ @ pingSandboxKernel @ kernel := kernel;
checkSandboxKernel[ kernel_LinkObject ] := startSandboxKernel[ ];
checkSandboxKernel // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*pingSandboxKernel*)
pingSandboxKernel // beginDefinition;

pingSandboxKernel[ kernel_LinkObject ] := Enclose[
    Module[ { uuid, return },

        uuid   = CreateUUID[ ];
        return = $Failed;

        ConfirmMatch[
            TimeConstrained[
                While[ LinkReadyQ @ kernel, LinkRead @ kernel ],
                $sandboxPingTimeout,
                $TimedOut
            ],
            Except[ $TimedOut ],
            "InitialLinkRead"
        ];

        With[ { id = uuid }, LinkWrite[ kernel, Unevaluated @ EvaluatePacket @ { id, $ProcessID } ] ];

        ConfirmMatch[
            TimeConstrained[
                While[ ! MatchQ[ return = LinkRead @ kernel, ReturnPacket @ { uuid, _ } ] ],
                $sandboxPingTimeout,
                $TimedOut
            ],
            Except[ $TimedOut ],
            "LinkReadReturn"
        ];

        ConfirmBy[
            Replace[ return, ReturnPacket @ { _, pid_ } :> pid ],
            IntegerQ,
            "ProcessID"
        ]
    ]
];

pingSandboxKernel // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*Start Kernel*)

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*startSandboxKernel*)
startSandboxKernel // beginDefinition;

startSandboxKernel[ ] := Enclose[
    Module[ { pwFile, kernel, readPaths, writePaths, executePaths, pid },

        Scan[ LinkClose, Select[ Links[ ], sandboxKernelQ ] ];

        (* pwFile = FileNameJoin @ { $InstallationDirectory, "Configuration", "Licensing", "playerpass" }; *)

        kernel = ConfirmMatch[ LinkLaunch @ $sandboxKernelCommandLine, _LinkObject, "LinkLaunch" ];

        readPaths    = makePaths @ toolOptionValue[ "WolframLanguageEvaluator", "AllowedReadPaths"    ];
        writePaths   = makePaths @ toolOptionValue[ "WolframLanguageEvaluator", "AllowedWritePaths"   ];
        executePaths = makePaths @ toolOptionValue[ "WolframLanguageEvaluator", "AllowedExecutePaths" ];

        (* Use StartProtectedMode instead of passing the -sandbox argument, since we need to initialize the FE first *)
        With[ { read = readPaths, write = writePaths, execute = executePaths },
            LinkWrite[
                kernel,
                Unevaluated @ EvaluatePacket[
                    UsingFrontEnd @ Null;
                    SetOptions[ First @ Streams[ "stdout" ], PageWidth -> Infinity ];
                    Developer`StartProtectedMode[ "Read" -> read, "Write" -> write, "Execute" -> execute ]
                ]
            ]
        ];

        pid = pingSandboxKernel @ kernel;

        With[ { messages = $messageOverrides },
            LinkWrite[
                kernel,
                Unevaluated @ EnterExpressionPacket[
                    (* Redefine some messages to provide hints to the LLM: *)
                    ReleaseHold @ messages;

                    (* Reset line number and leave `In[1]:=` in the buffer *)
                    $Line = 0
                ]
            ]
        ];

        TimeConstrained[
            While[ ! MatchQ[ LinkRead @ kernel, _ReturnExpressionPacket ] ],
            $sandboxPingTimeout,
            Confirm[ $Failed, "LineReset" ]
        ];

        If[ IntegerQ @ pid,
            $SandboxKernel = kernel,
            Quiet @ LinkClose @ kernel;
            throwFailure[ "NoSandboxKernel" ]
        ]
    ],
    throwInternalFailure[ startSandboxKernel[ ], ## ] &
];

startSandboxKernel // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*makePaths*)
makePaths // beginDefinition;
makePaths[ All ] := If[ $OperatingSystem === "Windows", # <> ":\\" & /@ CharacterRange[ "A", "Z" ], "/" ];
makePaths[ None ] := { };
makePaths[ paths_List ] := DeleteDuplicates @ Flatten[ makePaths /@ paths ];
makePaths[ path_String ] := path;
makePaths[ Automatic|Inherited|_Missing ] := Automatic;
makePaths // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*$messageOverrides*)
$messageOverrides := $messageOverrides = Flatten @ Apply[
    HoldComplete,
    ReadList[
        PacletObject[ "Wolfram/Chatbook" ][ "AssetLocation", "SandboxMessages" ],
        HoldComplete @ Expression
    ]
];

(* ::**************************************************************************************************************:: *)
(* ::Section::Closed:: *)
(*Evaluate*)

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*sandboxEvaluate*)
sandboxEvaluate // beginDefinition;

sandboxEvaluate[ KeyValuePattern[ "code" -> code_ ] ] := sandboxEvaluate @ code;
sandboxEvaluate[ code_String ] := sandboxEvaluate @ toSandboxExpression @ code;
sandboxEvaluate[ HoldComplete[ xs__, x_ ] ] := sandboxEvaluate @ HoldComplete @ CompoundExpression[ xs, x ];
sandboxEvaluate[ HoldComplete[ evaluation_ ] ] /; $CloudEvaluation := cloudSandboxEvaluate @ HoldComplete @ evaluation;

sandboxEvaluate[ HoldComplete[ evaluation_ ] ] := Enclose[
    Module[ { kernel, null, packets, $sandboxTag, $timedOut, results, flat, initialized },

        $lastSandboxEvaluation = HoldComplete @ evaluation;

        kernel = ConfirmMatch[ getSandboxKernel[ ], _LinkObject, "GetKernel" ];

        ConfirmMatch[ linkWriteEvaluation[ kernel, evaluation ], Null, "LinkWriteEvaluation" ];

        { null, { packets } } = ConfirmMatch[
            Reap[
                Sow[ Nothing, $sandboxTag ];
                TimeConstrained[
                    While[ ! MatchQ[ Sow[ LinkRead @ kernel, $sandboxTag ], _ReturnExpressionPacket ] ],
                    2 * $sandboxEvaluationTimeout,
                    $timedOut
                ],
                $sandboxTag
            ],
            { _, { _List } },
            "LinkRead"
        ];

        If[ null === $timedOut,
            AppendTo[
                packets,
                With[ { fail = timeConstraintFailure @ $sandboxEvaluationTimeout },
                    ReturnExpressionPacket @ HoldComplete @ fail
                ]
            ]
        ];

        results = Cases[ packets, ReturnExpressionPacket[ expr_ ] :> expr ];

        flat = Flatten[ HoldComplete @@ results, 1 ];

        initialized = initializeExpressions @ flat;

        (* TODO: include prompting that explains how to use Out[n] to get previous results *)

        $lastSandboxResult = <|
            "String"  -> sandboxResultString[ initialized, packets ],
            "Result"  -> sandboxResult @ initialized,
            "Packets" -> packets
        |>
    ],
    throwInternalFailure[ sandboxEvaluate @ HoldComplete @ evaluation, ## ] &
];

sandboxEvaluate // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*cloudSandboxEvaluate*)
cloudSandboxEvaluate // beginDefinition;

cloudSandboxEvaluate[ HoldComplete[ evaluation_ ] ] := Enclose[
    Catch @ Module[ { api, held, wxf, definitions, response, result, packets, initialized },

        $lastSandboxEvaluation = HoldComplete @ evaluation;

        api = ConfirmMatch[ getCloudEvaluatorAPI[ ], _CloudObject|_Failure, "CloudEvaluator" ];
        If[ FailureQ @ api, Throw @ api ];
        held = ConfirmMatch[ makeCloudEvaluation @ evaluation, HoldComplete[ _ ], "Evaluation" ];
        wxf = ConfirmBy[ BinarySerialize[ held, PerformanceGoal -> "Size" ], ByteArrayQ, "WXF" ];
        definitions = makeCloudDefinitionsWXF @ HoldComplete @ evaluation;

        response = ConfirmMatch[
            URLExecute[
                HTTPRequest[
                    api,
                    <|
                        "Method" -> "POST",
                        "Body" -> {
                            "Evaluation" -> BaseEncode @ wxf,
                            "TimeConstraint" -> $sandboxEvaluationTimeout,
                            If[ ByteArrayQ @ definitions  , "Definitions" -> BaseEncode @ definitions  , Nothing ],
                            If[ ByteArrayQ @ $cloudSession, "SessionMX"   -> BaseEncode @ $cloudSession, Nothing ]
                        }
                    |>
                ],
                "WXF"
            ],
            KeyValuePattern[ (Rule|RuleDelayed)[ "Result", _HoldComplete ] ] | _Failure,
            "Response"
        ];

        If[ FailureQ @ response, Throw @ response ];

        result = ConfirmMatch[ Lookup[ response, "Result" ], _HoldComplete, "Result" ];
        packets = TextPacket /@ Flatten @ { response[ "OutputLog" ], response[ "MessagesText" ] };
        initialized = initializeExpressions @ result;

        $lastSandboxResult = <|
            "String"    -> sandboxResultString[ initialized, packets ],
            "Result"    -> sandboxResult @ initialized,
            "Packets"   -> packets,
            "SessionMX" -> setCloudSessionString @ response
        |>
    ],
    throwInternalFailure
];

cloudSandboxEvaluate // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*setCloudSessionString*)
setCloudSessionString // beginDefinition;
setCloudSessionString[ KeyValuePattern[ "SessionMX" -> mx_ ] ] := setCloudSessionString @ mx;
setCloudSessionString[ mx_ByteArray ] := $cloudSession = mx;
setCloudSessionString[ s_String ] := setCloudSessionString @ ByteArray @ s;
setCloudSessionString // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*makeCloudEvaluation*)
makeCloudEvaluation // beginDefinition;
makeCloudEvaluation // Attributes = { HoldAllComplete };

makeCloudEvaluation[ evaluation_ ] :=
    With[ { line = $cloudLineNumber++ },
        makeLinkWriteEvaluation[ $Line = line; evaluation ]
    ];

makeCloudEvaluation // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*getCloudEvaluatorAPI*)
getCloudEvaluatorAPI // beginDefinition;

getCloudEvaluatorAPI[ ] :=
    getCloudEvaluatorAPI @ CloudObject @ $cloudEvaluatorLocation;

getCloudEvaluatorAPI[ target_CloudObject ] :=
    Module[ { deployed },
        deployed = deployCloudEvaluator @ target;
        If[ validCloudEvaluatorQ @ deployed,
            getCloudEvaluatorAPI[ ] = deployed,
            getCloudEvaluatorAPI[ ] = Failure[
                "CloudEvaluatorUnavailable",
                <|
                    "MessageTemplate"   -> "No cloud evaluator available.",
                    "MessageParameters" -> { }
                |>
            ]
        ]
    ];

getCloudEvaluatorAPI // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsubsection::Closed:: *)
(*validCloudEvaluatorQ*)
validCloudEvaluatorQ // beginDefinition;

validCloudEvaluatorQ[ obj_CloudObject ] := MatchQ[
    URLExecute[ obj, { "Evaluation" -> BaseEncode @ BinarySerialize @ HoldComplete[ 1 + 1 ] }, "WXF" ],
    KeyValuePattern[ (Rule|RuleDelayed)[ "Result", HoldComplete[ 2 ] ] ]
];

validCloudEvaluatorQ // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsubsection::Closed:: *)
(*deployCloudEvaluator*)
deployCloudEvaluator // beginDefinition;

deployCloudEvaluator[ target_CloudObject ] := With[ { messages = $messageOverrides },
    CloudDeploy[
        APIFunction[
            {
                "Evaluation"     -> "String",
                "Definitions"    -> "String" -> None,
                "SessionMX"      -> "String" -> None,
                "TimeConstraint" -> "Number" -> $sandboxEvaluationTimeout
            },
            Function @ Module[ { file },

                (* Clear existing global symbols *)
                Remove[ "Global`*" ];

                (* Define custom message text *)
                ReleaseHold @ messages;

                (* Forward user definitions *)
                If[ StringQ @ #Definitions,
                    Language`ExtendedFullDefinition[ ] = BinaryDeserialize @ BaseDecode[ #Definitions ]
                ];

                (* Restore definitions from previous session *)
                file = FileNameJoin @ { $TemporaryDirectory, "Session.mx" };
                If[ StringQ @ #SessionMX,
                    BinaryWrite[ file, ByteArray[ #SessionMX ] ];
                    Close @ file;
                    Get @ file;
                ];

                (* Evaluate the input *)
                BinarySerialize[
                    Append[
                        EvaluationData[
                            HoldComplete @@ {
                                TimeConstrained[
                                    BinaryDeserialize[ BaseDecode[ #Evaluation ], ReleaseHold ],
                                    #TimeConstraint,
                                    Failure[
                                        "EvaluationTimeExceeded",
                                        <|
                                            "MessageTemplate"   -> "Evaluation exceeded the `1` second time limit.",
                                            "MessageParameters" -> { #TimeConstraint }
                                        |>
                                    ]
                                ]
                            }
                        ],
                        (* Save any new definitions as a session byte array *)
                        "SessionMX" -> (
                            DumpSave[ file, "Global`", "SymbolAttributes" -> False ];
                            ReadByteArray @ file
                        )
                    ],
                    PerformanceGoal -> "Size"
                ]
            ],
            "Binary"
        ],
        target,
        EvaluationPrivileges -> None,
        Permissions          -> "Private"
    ]
];

deployCloudEvaluator // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*initializeExpressions*)
initializeExpressions // beginDefinition;

initializeExpressions[ flat: HoldComplete @ Association @ OrderlessPatternSequence[ "Initialized" -> pos0_, ___ ] ] :=
    With[ { pos = { 1, Key[ "Result" ], ## } & @@@ pos0 },
        ReplacePart[ flat, Thread[ pos -> Extract[ flat, pos ] ] ]
    ];

initializeExpressions[ failed: HoldComplete[ _Failure|$Failed|$Aborted ] ] :=
    failed;

initializeExpressions // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*toSandboxExpression*)
toSandboxExpression // beginDefinition;

toSandboxExpression[ s_String ] := toSandboxExpression[ s, Quiet @ ToExpression[ s, InputForm, HoldComplete ] ];

toSandboxExpression[ s_, expr_HoldComplete ] := expr;

toSandboxExpression[ s_String, $Failed ] /; StringContainsQ[ s, "'" ] :=
    Module[ { new, held },
        new = StringReplace[ s, "'" -> "\"" ];
        held = Quiet @ ToExpression[ new, InputForm, HoldComplete ];
        If[ MatchQ[ held, _HoldComplete ],
            sandboxStringNormalize[ s ] = new;
            held,
            HoldComplete[ ToExpression[ s, InputForm ] ]
        ]
    ];

toSandboxExpression[ s_String, $Failed ] := HoldComplete @ ToExpression[ s, InputForm ];

toSandboxExpression // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsubsection::Closed:: *)
(*sandboxStringNormalize*)
sandboxStringNormalize // beginDefinition;
sandboxStringNormalize[ s_String ] := s;
sandboxStringNormalize // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*linkWriteEvaluation*)
linkWriteEvaluation // beginDefinition;
linkWriteEvaluation // Attributes = { HoldAllComplete };

linkWriteEvaluation[ kernel_, evaluation_ ] :=
    With[ { eval = includeDefinitions @ makeLinkWriteEvaluation @ evaluation },
        LinkWrite[ kernel, Unevaluated @ EnterExpressionPacket @ ReleaseHold @ eval ]
    ];

linkWriteEvaluation // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*makeLinkWriteEvaluation*)
makeLinkWriteEvaluation // beginDefinition;
makeLinkWriteEvaluation // Attributes = { HoldAllComplete };

makeLinkWriteEvaluation[ evaluation_ ] := Enclose[
    Module[ { eval, constrained },
        eval = ConfirmMatch[ createEvaluationWithWarnings @ evaluation, HoldComplete[ _ ], "Warnings" ];
        constrained = ConfirmMatch[ addTimeConstraint @ eval, HoldComplete[ _ ], "TimeConstraint" ];
        ConfirmMatch[ addInitializations @ constrained, HoldComplete[ _ ], "Initializations" ]
    ],
    throwInternalFailure
];

makeLinkWriteEvaluation // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*includeDefinitions*)
includeDefinitions // beginDefinition;

includeDefinitions[ eval_HoldComplete ] :=
    includeDefinitions[ eval, $includeDefinitions ];

includeDefinitions[ h: HoldComplete[ eval___ ], True|$$unspecified ] :=
    With[ { def = Language`ExtendedFullDefinition @ h },
        HoldComplete[ Language`ExtendedFullDefinition[ ] = def; eval ] /; MatchQ[ def, _Language`DefinitionList ]
    ];

includeDefinitions[ h_HoldComplete, _ ] :=
    h;

includeDefinitions // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*makeCloudDefinitionsWXF*)
makeCloudDefinitionsWXF // beginDefinition;

makeCloudDefinitionsWXF[ eval_HoldComplete ] :=
    makeCloudDefinitionsWXF[ eval, $includeDefinitions ];

makeCloudDefinitionsWXF[ h_HoldComplete, True|$$unspecified ] :=
    With[ { def = Language`ExtendedFullDefinition @ h },
        BinarySerialize[ def, PerformanceGoal -> "Size" ] /; MatchQ[ def, _Language`DefinitionList ]
    ];

makeCloudDefinitionsWXF[ h_HoldComplete, _ ] :=
    None;

makeCloudDefinitionsWXF // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*addInitializations*)
addInitializations // beginDefinition;

addInitializations[ eval_HoldComplete ] := addInitializations[ eval, $initializationTest ];

addInitializations[ HoldComplete[ eval_ ], initializedQ_ ] :=
    HoldComplete @ With[ { result = HoldComplete @@ { eval } },
        <|
            "Line"        -> $Line,
            "Result"      -> result,
            "Initialized" -> Position[ result, _? initializedQ, Heads -> True ]
        |>
    ];

addInitializations // endDefinition;


$initializationTest := $initializationTest = Module[ { tests, slot, func },
    tests = Flatten[ HoldComplete @@ Cases[ $initializationTests, f_ :> HoldComplete @ f @ Unevaluated @ slot[ 1 ] ] ];
    func = Replace[ tests, HoldComplete[ t___ ] :> Function[ Null, TrueQ @ Or @ t, HoldAllComplete ] ];
    func /. slot -> Slot
];

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*addTimeConstraint*)
addTimeConstraint // beginDefinition;
addTimeConstraint[ eval_HoldComplete ] := addTimeConstraint[ eval, $sandboxEvaluationTimeout ];
addTimeConstraint[ eval_, t_ ] := addTimeConstraint[ eval, t, timeConstraintFailure @ t ];
addTimeConstraint[ HoldComplete[ eval_ ], t_, fail_Failure ] := HoldComplete @ TimeConstrained[ eval, t, fail ];
addTimeConstraint // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsubsection::Closed:: *)
(*timeConstraintFailure*)
timeConstraintFailure // beginDefinition;

timeConstraintFailure[ t_? Positive ] := Failure[
    "EvaluationTimeExceeded",
    <|
        "MessageTemplate"   -> "Evaluation exceeded the `1` second time limit.",
        "MessageParameters" -> { t }
    |>
];

timeConstraintFailure[ q_Quantity ] :=
    With[ { s = UnitConvert[ q, "Seconds" ] },
        timeConstraintFailure @ QuantityMagnitude @ s /; QuantityUnit @ s === "Seconds"
    ];

timeConstraintFailure // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*createEvaluationWithWarnings*)
createEvaluationWithWarnings // beginDefinition;
createEvaluationWithWarnings // Attributes = { HoldAllComplete };

createEvaluationWithWarnings[ evaluation_ ] :=
    Module[ { held, undefined },
        held = Flatten @ HoldComplete @ evaluation;

        undefined = Flatten[ HoldComplete @@ Cases[
            Unevaluated @ evaluation,
            s_Symbol? undefinedSymbolQ :> HoldComplete @ s,
            Infinity,
            Heads -> True
        ] ];

        (* TODO: add other warnings *)
        addWarnings[ held, <| "UndefinedSymbols" -> undefined |> ]
    ];

createEvaluationWithWarnings // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*addWarnings*)
addWarnings // beginDefinition;

addWarnings[ HoldComplete[ eval__ ], as: KeyValuePattern[ "UndefinedSymbols" -> HoldComplete[ ] ] ] :=
    addWarnings[ HoldComplete[ eval ], KeyDrop[ as, "UndefinedSymbols" ] ];

addWarnings[ HoldComplete[ eval__ ], as: KeyValuePattern[ "UndefinedSymbols" -> HoldComplete[ s_Symbol ] ] ] :=
    addWarnings[ HoldComplete[ Message[ Symbol::undefined, s ]; eval ], KeyDrop[ as, "UndefinedSymbols" ] ];

addWarnings[ HoldComplete[ eval__ ], as: KeyValuePattern[ "UndefinedSymbols" -> HoldComplete[ s__Symbol ] ] ] :=
    addWarnings[
        HoldComplete[ Message[ Symbol::undefined2, StringRiffle[ { s }, ", " ] ]; eval ],
        KeyDrop[ as, "UndefinedSymbols" ]
    ];

addWarnings[ HoldComplete[ eval_  ], _ ] := addMessageHandler @ HoldComplete @ eval;
addWarnings[ HoldComplete[ eval__ ], _ ] := addMessageHandler @ HoldComplete @ CompoundExpression @ eval;

addWarnings // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*addMessageHandler*)
addMessageHandler // beginDefinition;

addMessageHandler[ HoldComplete[ eval_ ] ] :=
    HoldComplete @ WithCleanup[
        eval,
        If[ MatchQ[ $MessageList, { __ } ], Message[ General::messages ] ]
    ];

addMessageHandler // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*undefinedSymbolQ*)
undefinedSymbolQ // ClearAll;
undefinedSymbolQ // Attributes = { HoldAllComplete };

undefinedSymbolQ[ symbol_Symbol ] := TrueQ @ And[
    AtomQ @ Unevaluated @ symbol,
    Unevaluated @ symbol =!= Internal`$EFAIL,
    Context @ Unevaluated @ symbol === "Global`",
    StringStartsQ[ SymbolName @ Unevaluated @ symbol, _? UpperCaseQ ],
    ! System`Private`HasAnyEvaluationsQ @ symbol
];

undefinedSymbolQ[ ___ ] := False;

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*sandboxResult*)
sandboxResult // beginDefinition;
sandboxResult[ HoldComplete @ Association @ OrderlessPatternSequence[ "Result" -> res_, ___ ] ] := sandboxResult @ res;
sandboxResult[ HoldComplete[ held_HoldComplete ] ] := sandboxResult @ held;
sandboxResult[ HoldComplete[ ___, expr_ ] ] := HoldForm @ expr;
sandboxResult[ res_ ] := HoldForm @ res;
sandboxResult // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*sandboxResultString*)
sandboxResultString // beginDefinition;
sandboxResultString[ result_, packets_ ] := checkDocSearchMessageStrings @ sandboxResultString0[ result, packets ];
sandboxResultString // endDefinition;


sandboxResultString0 // beginDefinition;

sandboxResultString0[ result_, packets_ ] := sandboxResultString0 @ result;

sandboxResultString0[ HoldComplete[ KeyValuePattern @ { "Line" -> line_, "Result" -> result_ } ], packets_ ] :=
    StringRiffle[
        Flatten @ {
            makePacketMessages[ ToString @ line, packets ],
            "Out[" <> ToString @ line <> "]= " <> sandboxResultString0 @ Flatten @ HoldComplete @ result
        },
        "\n"
    ];

sandboxResultString0[ HoldComplete[ ___, expr_? outputFormQ ] ] :=
    With[ { string = fixLineEndings @ ToString[ Unevaluated @ expr, PageWidth -> 100 ] },
        If[ StringLength @ string < $toolResultStringLength,
            If[ StringContainsQ[ string, "\n" ], "\n" <> string, string ],
            StringJoin[
                "\n",
                stringTrimMiddle[ string, $toolResultStringLength ],
                "\n\n\n",
                makeExpressionURI[ "expression", "Formatted Result", Unevaluated @ expr ]
            ]
        ]
    ];

sandboxResultString0[ HoldComplete[ ___, expr_? simpleResultQ ] ] :=
    With[ { string = fixLineEndings @ ToString[ Unevaluated @ expr, InputForm, PageWidth -> 100 ] },
        If[ StringLength @ string < $toolResultStringLength,
            If[ StringContainsQ[ string, "\n" ], "\n" <> string, string ],
            StringJoin[
                "\n",
                fixLineEndings @ ToString[
                    Unevaluated @ Short[ expr, Floor[ $toolResultStringLength / 100 ] ],
                    OutputForm,
                    PageWidth -> 100
                ],
                "\n\n\n",
                makeExpressionURI[ "expression", "Formatted Result", Unevaluated @ expr ]
            ]
        ]
    ];

sandboxResultString0[ HoldComplete[ ___, expr_ ] ] := makeExpressionURI @ Unevaluated @ expr;

sandboxResultString0[ HoldComplete[ ] ] := "Null";

sandboxResultString0 // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*checkDocSearchMessageStrings*)
checkDocSearchMessageStrings // beginDefinition;
checkDocSearchMessageStrings[ string_String ] /; KeyExistsQ[ $selectedTools, "DocumentationSearcher" ] := string;
checkDocSearchMessageStrings[ string_String ] := StringDelete[ string, $docSearchMessageStrings ];
checkDocSearchMessageStrings // endDefinition;

$docSearchMessageStrings = {
    " Use the documentation_searcher tool to find solutions.",
    " Use the documentation_searcher tool to find alternatives."
};

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*outputFormQ*)
outputFormQ // beginDefinition;
outputFormQ[ $$outputForm[ ___ ] ] := True;
outputFormQ[ _ ] := False;
outputFormQ // Attributes = { HoldAllComplete };
outputFormQ // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*initializedQ*)
initializedQ // beginDefinition;
initializedQ // Attributes = { HoldAllComplete };
initializedQ[ expr_ ] := $initializationTest @ Unevaluated @ expr;
initializedQ // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*simpleResultQ*)
simpleResultQ // beginDefinition;
simpleResultQ // Attributes = { HoldAllComplete };
simpleResultQ[ expr_ ] := FreeQ[ Unevaluated @ expr, _? fancyResultQ ];
simpleResultQ // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*fancyResultQ*)
fancyResultQ // beginDefinition;
fancyResultQ // Attributes = { HoldAllComplete };
fancyResultQ[ _Manipulate|_DynamicModule|_Video|_Audio|_Tree ] := True;
fancyResultQ[ gfx_ ] := graphicsQ @ Unevaluated @ gfx;
fancyResultQ // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*makePacketMessages*)
makePacketMessages // beginDefinition;
makePacketMessages[ line_, packets_List ] := makePacketMessages[ line, # ] & /@ packets;
makePacketMessages[ line_String, TextPacket[ text_String ] ] := text;
makePacketMessages[ line_, _InputNamePacket|_MessagePacket|_OutputNamePacket|_ReturnExpressionPacket ] := Nothing;
makePacketMessages // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*sandboxFormatter*)
sandboxFormatter // beginDefinition;

sandboxFormatter[ code_String, "Parameters", "code" ] :=
    RawBoxes @ makeInteractiveCodeCell[ "Wolfram", sandboxStringNormalize @ code ];

sandboxFormatter[ KeyValuePattern[ "Result" -> result_ ], "Result" ] :=
    sandboxFormatter[ result, "Result" ];

sandboxFormatter[ result_, "Result" ] :=
    RawBoxes @ makeInteractiveCodeCell[ "Wolfram", Cell[ BoxData @ MakeBoxes @ result, "Input" ] ];

sandboxFormatter[ result_, ___ ] := result;

sandboxFormatter // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Section::Closed:: *)
(*Package Footer*)

(* Close previous sandbox kernel if package is being reloaded: *)
Scan[ LinkClose, Select[ Links[ ], sandboxKernelQ ] ];

If[ Wolfram`ChatbookInternal`$BuildingMX,
    $messageOverrides;
    $initializationTest;
];

(* :!CodeAnalysis::EndBlock:: *)

End[ ];
EndPackage[ ];
