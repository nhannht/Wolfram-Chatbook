(* ::Package:: *)

(* :!CodeAnalysis::BeginBlock:: *)
(* :!CodeAnalysis::Disable::NoVariables::Module:: *)
(* :!CodeAnalysis::Disable::SuspiciousSessionSymbol:: *)

BeginPackage["Wolfram`Chatbook`UI`"]

(* Avoiding context aliasing due to bug 434990: *)
Needs[ "GeneralUtilities`" -> None ];

MakeChatInputActiveCellDingbat
MakeChatInputCellDingbat
MakeChatDelimiterCellDingbat
MakeChatCloudDockedCellContents

GeneralUtilities`SetUsage[CreatePreferencesContent, "
CreatePreferencesContent[] returns an expression containing the UI shown in the Preferences > AI Settings window.
"]

GeneralUtilities`SetUsage[CreateToolbarContent, "
CreateToolbarContent[] is called by the NotebookToolbar to generate the content of the 'Notebook AI Settings' attached menu.
"]

HoldComplete[
    `getPersonaIcon;
    `getPersonaMenuIcon;
    `personaDisplayName;
    `resizeMenuIcon;
    `serviceIcon;
    `tr;
    `getModelMenuIcon;
    `makeToolCallFrequencySlider;
    `makeTemperatureSlider;
    `labeledCheckbox;
    `showSnapshotModelsQ;
    `makeAutomaticResultAnalysisCheckbox;
];

Begin["`Private`"]

Needs[ "Wolfram`Chatbook`"                    ];
Needs[ "Wolfram`Chatbook`Actions`"            ];
Needs[ "Wolfram`Chatbook`Common`"             ];
Needs[ "Wolfram`Chatbook`Dynamics`"           ];
Needs[ "Wolfram`Chatbook`Errors`"             ];
Needs[ "Wolfram`Chatbook`ErrorUtils`"         ];
Needs[ "Wolfram`Chatbook`FrontEnd`"           ];
Needs[ "Wolfram`Chatbook`Menus`"              ];
Needs[ "Wolfram`Chatbook`Models`"             ];
Needs[ "Wolfram`Chatbook`Personas`"           ];
Needs[ "Wolfram`Chatbook`PreferencesContent`" ];
Needs[ "Wolfram`Chatbook`PreferencesUtils`"   ];
Needs[ "Wolfram`Chatbook`Serialization`"      ];
Needs[ "Wolfram`Chatbook`Services`"           ];
Needs[ "Wolfram`Chatbook`Settings`"           ];
Needs[ "Wolfram`Chatbook`Utils`"              ];

(* ::**************************************************************************************************************:: *)
(* ::Section::Closed:: *)
(*Configuration*)
$chatMenuWidth = 220;

(* ::**************************************************************************************************************:: *)
(* ::Section::Closed:: *)
(*Cloud Toolbar*)

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*MakeChatCloudDockedCellContents*)
MakeChatCloudDockedCellContents[] := Grid[
	{{
		Item[$cloudChatBanner, Alignment -> Left],
		Item["", ItemSize -> Fit],
		Row[{"Persona", Spacer[5], trackedDynamic[$cloudPersonaChooser, "Personas"]}],
		Row[{"Model", Spacer[5], trackedDynamic[$cloudModelChooser, "Models"]}]
	}},
	Dividers -> {{False, False, False, True}, False},
	Spacings -> {2, 0},
	BaseStyle -> {"Text", FontSize -> 14, FontColor -> GrayLevel[0.4]},
	FrameStyle -> Directive[Thickness[2], GrayLevel[0.9]]
]

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*$cloudPersonaChooser*)
$cloudPersonaChooser := PopupMenu[
	Dynamic[
		Replace[
			CurrentValue[EvaluationNotebook[], {TaggingRules, "ChatNotebookSettings", "LLMEvaluator"}],
			Inherited :> Lookup[$defaultChatSettings, "LLMEvaluator", "CodeAssistant"]
		],
		Function[CurrentValue[EvaluationNotebook[], {TaggingRules, "ChatNotebookSettings", "LLMEvaluator"}] = #]
	],
	KeyValueMap[
		Function[{key, as}, key -> Grid[{{resizeMenuIcon[getPersonaMenuIcon[as]], personaDisplayName[key, as]}}]],
		GetCachedPersonaData[]
	],
	ImageSize -> {Automatic, 30},
	Alignment -> {Left, Baseline},
	BaseStyle -> {FontSize -> 12}
]

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*$cloudModelChooser*)
$cloudModelChooser := PopupMenu[
	Dynamic[
		Replace[
			CurrentValue[EvaluationNotebook[], {TaggingRules, "ChatNotebookSettings", "Model"}],
			Inherited :> Lookup[$defaultChatSettings, "Model", "gpt-3.5-turbo"]
		],
		Function[CurrentValue[EvaluationNotebook[], {TaggingRules, "ChatNotebookSettings", "Model"}] = #]
	],
	KeyValueMap[
		{modelName, settings} |-> (
			modelName -> Grid[{{getModelMenuIcon[settings], modelDisplayName[modelName]}}]
		),
        (* FIXME: use the new system *)
		getModelsMenuItems[]
	],
	ImageSize -> {Automatic, 30},
	Alignment -> {Left, Baseline},
	BaseStyle -> {FontSize -> 12}
]

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*$cloudChatBanner*)
$cloudChatBanner := PaneSelector[
    {
        True -> Grid[
			{
				{
					"",
					chatbookIcon[ "ChatDrivenNotebookIcon", False ],
					Style[
						"Chat-Driven Notebook",
						FontColor  -> RGBColor[ "#333333" ],
						FontFamily -> "Source Sans Pro",
						FontSize   -> 16,
						FontWeight -> "DemiBold"
					]
				}
			},
			Alignment -> { Automatic, Center },
			Spacings  -> 0.5
		],
        False -> Grid[
			{
				{
					"",
					chatbookIcon[ "ChatEnabledNotebookIcon", False ],
					Style[
						"Chat-Enabled Notebook",
						FontColor  -> RGBColor[ "#333333" ],
						FontFamily -> "Source Sans Pro",
						FontSize   -> 16,
						FontWeight -> "DemiBold"
					]
				}
			},
			Alignment -> { Automatic, Center },
			Spacings  -> 0.5
		]
    },
    Dynamic @ TrueQ @ CurrentValue[
		EvaluationNotebook[ ],
		{ TaggingRules, "ChatNotebookSettings", "ChatDrivenNotebook" }
	],
    ImageSize -> Automatic
]

(* ::**************************************************************************************************************:: *)
(* ::Section::Closed:: *)
(*Preferences Panel*)
CreatePreferencesContent[ ] := trackedDynamic[ createPreferencesContent[ ], { "Preferences" } ];

(* ::**************************************************************************************************************:: *)
(* ::Section::Closed:: *)
(*Default Notebook Toolbar*)
CreateToolbarContent[] := With[{
	nbObj = EvaluationNotebook[],
	menuCell = EvaluationCell[]
},
	CurrentValue[menuCell, {TaggingRules, "IsChatEnabled"}] =
		TrueQ[CurrentValue[nbObj, {StyleDefinitions, "ChatInput", Evaluatable}]];

	PaneSelector[
		{
			True :> (
				Dynamic[ makeToolbarMenuContent @ menuCell, SingleEvaluation -> True, DestroyAfterEvaluation -> True ]
			),
			False :> (
				Dynamic @ Refresh[
					createChatNotEnabledToolbar[nbObj, menuCell],
					None
				]
			)
		},
		Dynamic @ CurrentValue[menuCell, {TaggingRules, "IsChatEnabled"}],
		ImageSize -> Automatic
	]
];

makeToolbarMenuContent[ menuCell_ ] := Enclose[
    Module[ { items, item1, item2, new },

        items = ConfirmBy[ makeChatActionMenu[ "Toolbar", EvaluationNotebook[ ], Automatic, "List" ], ListQ, "Items" ];

        item1 = Pane[
            makeEnableAIChatFeaturesLabel @ True,
            ImageMargins -> { { 5, 20 }, { 2.5, 2.5 } }
        ];

        item2 = Pane[
            makeAutomaticResultAnalysisCheckbox @ EvaluationNotebook[ ],
            ImageMargins -> { { 5, 20 }, { 2.5, 2.5 } }
        ];

        new = Join[ { { None, item1, None }, { None, item2, None } }, items ];

        MakeMenu[ new, Transparent, $chatMenuWidth ]
    ],
    throwInternalFailure
];

(*====================================*)

SetFallthroughError[createChatNotEnabledToolbar]

createChatNotEnabledToolbar[
	nbObj_NotebookObject,
	menuCell_CellObject
] := Module[{
	button
},
	button = EventHandler[
		makeEnableAIChatFeaturesLabel[False],
		"MouseClicked" :> (
			tryMakeChatEnabledNotebook[nbObj, menuCell]
		),
		(* Needed so that we can open a ChoiceDialog if required. *)
		Method -> "Queued"
	];

	Pane[button, {$chatMenuWidth, Automatic}]
]

(*====================================*)

SetFallthroughError[tryMakeChatEnabledNotebook]

tryMakeChatEnabledNotebook[
	nbObj_NotebookObject,
	menuCell_CellObject
] := Module[{
	useChatbookStylesheet
},
	useChatbookStylesheet = ConfirmReplace[CurrentValue[nbObj, StyleDefinitions], {
		"Default.nb" -> True,
		(* TODO: Generate a warning dialog in this case, because Chatbook.nb
			inherits from Default.nb? *)
		_?StringQ | _FrontEnd`FileName -> True,
		_ :> RaiseConfirmMatch[
			ChoiceDialog[
				Column[{
					Item[Magnify["\[WarningSign]", 5], Alignment -> Center],
					"",
					RawBoxes @ Cell[
						"Enabling Chat Notebook functionality will destroy the" <>
						" private styles defined in this notebook, and replace" <>
						" them with the shared Chatbook stylesheet.",
						"Text"
					],
					"",
					RawBoxes @ Cell["Are you sure you wish to continue?", "Text"]
				}],
				Background -> White
			],
			_?BooleanQ
		]
	}];

	RaiseAssert[BooleanQ[useChatbookStylesheet]];

	If[!useChatbookStylesheet,
		Return[Null, Module];
	];

	SetOptions[nbObj, StyleDefinitions -> "Chatbook.nb"];

	(* Cause the PaneSelector to switch to showing all the options allowed
		for Chat-Enabled notebooks. *)
	CurrentValue[menuCell, {TaggingRules, "IsChatEnabled"}] = True;
]

(*====================================*)

SetFallthroughError[makeEnableAIChatFeaturesLabel]

makeEnableAIChatFeaturesLabel[enabled_?BooleanQ] :=
	labeledCheckbox[enabled, "Enable AI Chat Features", !enabled]

(*====================================*)

SetFallthroughError[makeAutomaticResultAnalysisCheckbox]

makeAutomaticResultAnalysisCheckbox[
	target : _FrontEndObject | $FrontEndSession | _NotebookObject
] := With[{
	setterFunction = ConfirmReplace[target, {
		$FrontEnd | $FrontEndSession :> (
			Function[{newValue},
				CurrentValue[
					target,
					{TaggingRules, "ChatNotebookSettings", "Assistance"}
				] = newValue;
			]
		),
		nbObj_NotebookObject :> (
			Function[{newValue},
				(* If the new value is the same as the value inherited from the
				   parent scope, then set the value at the current level to
				   inherit from the parent.

				   Otherwise, if the new value differs from what would be
				   inherited from the parent, then override it at the current
				   level.

				   The consequence of this behavior is that the notebook-level
				   setting for Result Analysis will follow the global setting
				   _if_ the local value is clicked to set it equal to the global
				   setting.
				 *)
				If[
					SameQ[
						newValue,
						AbsoluteCurrentValue[
							$FrontEndSession,
							{TaggingRules, "ChatNotebookSettings", "Assistance"}
						]
					]
					,
					CurrentValue[
						nbObj,
						{TaggingRules, "ChatNotebookSettings", "Assistance"}
					] = Inherited
					,
					CurrentValue[
						nbObj,
						{TaggingRules, "ChatNotebookSettings", "Assistance"}
					] = newValue
				]
			]
		)
	}]
},
	labeledCheckbox[
		Dynamic[
			autoAssistQ[target],
			setterFunction
		],
		Row[{
			"Do automatic result analysis",
			Spacer[3],
			Tooltip[
				chatbookIcon["InformationTooltip", False],
				"If enabled, automatic AI provided suggestions will be added following evaluation results."
			]
		}]
	]
]

(*====================================*)

SetFallthroughError[labeledCheckbox]

labeledCheckbox[value_, label_, enabled_ : Automatic] :=
	Row[
		{
			Checkbox[
				value,
				{False, True},
				Enabled -> enabled
			],
			Spacer[3],
			label
		},
		BaseStyle -> {
			"Text",
			FontSize -> 14,
			(* Note: Workaround increased ImageMargins of Checkbox's in
			         Preferences.nb *)
			CheckboxBoxOptions -> { ImageMargins -> 0 }
		}
	]

(*====================================*)

makeToolCallFrequencySlider[ obj_ ] := Pane[
    Grid[
        {
            {
                labeledCheckbox[
                    Dynamic[
                        currentChatSettings[ obj, "ToolCallFrequency" ] === Automatic,
                        Function[
                            If[ TrueQ[ # ],
                                CurrentValue[ obj, { TaggingRules, "ChatNotebookSettings", "ToolCallFrequency" } ] = Inherited,
                                CurrentValue[ obj, { TaggingRules, "ChatNotebookSettings", "ToolCallFrequency" } ] = 0.5
                            ]
                        ]
                    ],
                    Style[ "Choose automatically", "ChatMenuLabel" ]
                ]
            },
            {
                Pane[
                    Slider[
                        Dynamic[
                            Replace[ currentChatSettings[ obj, "ToolCallFrequency" ], Automatic -> 0.5 ],
                            (CurrentValue[ obj, { TaggingRules, "ChatNotebookSettings", "ToolCallFrequency" } ] = #) &
                        ],
                        { 0, 1, 0.01 },
                        (* Enabled      -> Dynamic[ currentChatSettings[ obj, "ToolCallFrequency" ] =!= Automatic ], *)
                        ImageSize    -> { 150, Automatic },
                        ImageMargins -> { { 5, 0 }, { 5, 5 } }
                    ],
                    ImageSize -> { 180, Automatic },
                    BaseStyle -> { FontSize -> 12 }
                ],
                SpanFromLeft
            }
        },
        Alignment -> Left,
        Spacings  -> { Automatic, 0 }
    ],
    ImageMargins -> { { 5, 0 }, { 5, 5 } }
];

makeToolCallFrequencySlider[ obj_ ] :=
    Module[ { checkbox, slider },
        checkbox = labeledCheckbox[
            Dynamic[
                currentChatSettings[ obj, "ToolCallFrequency" ] === Automatic,
                Function[
                    If[ TrueQ[ # ],
                        CurrentValue[ obj, { TaggingRules, "ChatNotebookSettings", "ToolCallFrequency" } ] = Inherited,
                        CurrentValue[ obj, { TaggingRules, "ChatNotebookSettings", "ToolCallFrequency" } ] = 0.5
                    ]
                ]
            ],
            Style[ "Choose automatically", "ChatMenuLabel" ]
        ];
        slider = Pane[
            Grid[
                {
                    {
                        Style[ "Rare", "ChatMenuLabel", FontSize -> 12 ],
                        Slider[
                            Dynamic[
                                Replace[ currentChatSettings[ obj, "ToolCallFrequency" ], Automatic -> 0.5 ],
                                (CurrentValue[ obj, { TaggingRules, "ChatNotebookSettings", "ToolCallFrequency" } ] = #) &
                            ],
                            { 0, 1, 0.01 },
                            ImageSize    -> { 100, Automatic },
                            ImageMargins -> { { 0, 0 }, { 5, 5 } }
                        ],
                        Style[ "Often", "ChatMenuLabel", FontSize -> 12 ]
                    }
                },
                Spacings -> { { 0, { 0.5 }, 0 }, 0 },
                Alignment -> { { Left, Center, Right }, Baseline }
            ],
            ImageMargins -> 0,
            ImageSize    -> { 170, Automatic }
        ];
        Pane[
            PaneSelector[
                {
                    True -> Column[ { checkbox }, Alignment -> Left ],
                    False -> Column[ { slider, checkbox }, Alignment -> Left ]
                },
                Dynamic[ currentChatSettings[ obj, "ToolCallFrequency" ] === Automatic ],
                ImageSize -> Automatic
            ],
            ImageMargins -> { { 5, 0 }, { 5, 5 } }
        ]
    ];


makeTemperatureSlider[
	value_
] :=
	Pane[
		Slider[
			value,
			{ 0, 2, 0.01 },
			ImageSize  -> { 135, Automatic },
			ImageMargins -> {{5, 0}, {5, 5}},
			Appearance -> "Labeled"
		],
		ImageSize -> { 180, Automatic },
		BaseStyle -> { FontSize -> 12 }
	]

(*=========================================*)
(* Common preferences content construction *)
(*=========================================*)

showSnapshotModelsQ[] :=
	TrueQ @ CurrentValue[$FrontEnd, {
		PrivateFrontEndOptions,
		"InterfaceSettings",
		"ChatNotebooks",
		"ShowSnapshotModels"
	}]


(*========================================================*)

(* TODO: Make this look up translations for `name` in text resources data files. *)
tr[name_?StringQ] := name

(*


	Checkbox @ Dynamic[
		CurrentValue[$FrontEnd, {PrivateFrontEndOptions, "InterfaceSettings", "ChatNotebooks", "IncludeHistory"}]
	]

		- True -- include any history cells that the persona wants
		- False -- never include any history
		- {"Style1", "Style2", ...}
*)

(* ::**************************************************************************************************************:: *)
(* ::Section::Closed:: *)
(*Cell Dingbats*)

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*MakeChatInputActiveCellDingbat*)
MakeChatInputActiveCellDingbat[ ] :=
	DynamicModule[ { cell },
		trackedDynamic[ MakeChatInputActiveCellDingbat @ cell, { "ChatBlock" } ],
		Initialization :> (cell = EvaluationCell[ ]; Needs[ "Wolfram`Chatbook`" -> None ]),
		UnsavedVariables :> { cell }
	];

MakeChatInputActiveCellDingbat[cell_CellObject] := Module[{
	menuLabel,
	button
},
	(*-----------------------------------------*)
	(* Construct the action menu display label *)
	(*-----------------------------------------*)

	menuLabel = With[{
		personaValue = currentValueOrigin[
			parentCell @ cell,
			{TaggingRules, "ChatNotebookSettings", "LLMEvaluator"}
		]
	},
		getPersonaMenuIcon @ personaValue[[2]]
	];

	button = Button[
		Framed[
			Pane[menuLabel, Alignment -> {Center, Center}, ImageSize -> {25, 25}, ImageSizeAction -> "ShrinkToFit"],
			RoundingRadius -> 2,
			FrameStyle -> Dynamic[
				If[CurrentValue["MouseOver"], GrayLevel[0.74902], None]
			],
			Background -> Dynamic[
				If[CurrentValue["MouseOver"], GrayLevel[0.960784], None]
			],
			FrameMargins -> 0,
			ImageMargins -> 0,
			ContentPadding -> False
		],
		(
			AttachCell[
				EvaluationCell[],
				makeChatActionMenu[
					"Input",
					parentCell[EvaluationCell[]],
					EvaluationCell[]
				],
				{Left, Bottom},
				Offset[{0, 0}, {Left, Top}],
				{Left, Top},
				RemovalConditions -> {"EvaluatorQuit", "MouseClickOutside"}
			];
		),
		Appearance -> $suppressButtonAppearance,
		ImageMargins -> 0,
		FrameMargins -> 0,
		ContentPadding -> False
	];

	button
];

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*MakeChatInputCellDingbat*)
MakeChatInputCellDingbat[] :=
	PaneSelector[
		{
			True -> MakeChatInputActiveCellDingbat[],
			False -> Framed[
				RawBoxes @ TemplateBox[{}, "ChatIconUser"],
				RoundingRadius -> 3,
				FrameMargins -> 2,
				ImageMargins -> {{0, 3}, {0, 0}},
				FrameStyle -> Transparent,
				FrameMargins -> 0
			]
		},
		Dynamic[CurrentValue["MouseOver"]],
		ImageSize -> All
	]

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*MakeChatDelimiterCellDingbat*)
MakeChatDelimiterCellDingbat[ ] :=
	DynamicModule[ { cell },
		trackedDynamic[ MakeChatDelimiterCellDingbat @ cell, { "ChatBlock" } ],
		Initialization :> (
			cell = EvaluationCell[ ];
			Needs[ "Wolfram`Chatbook`" -> None ];
			updateDynamics[ "ChatBlock" ]
		),
		Deinitialization :> (
			Needs[ "Wolfram`Chatbook`" -> None ];
			updateDynamics[ "ChatBlock" ]
		),
		UnsavedVariables :> { cell }
	];

MakeChatDelimiterCellDingbat[cell_CellObject] := Module[{
	menuLabel,
	button
},
	(*-----------------------------------------*)
	(* Construct the action menu display label *)
	(*-----------------------------------------*)

	menuLabel = With[{
		personaValue = currentValueOrigin[
			parentCell @ cell,
			{TaggingRules, "ChatNotebookSettings", "LLMEvaluator"}
		]
	},
		getPersonaMenuIcon @ personaValue[[2]]
	];

	button = Button[
		Framed[
			Pane[menuLabel, Alignment -> {Center, Center}, ImageSize -> {25, 25}, ImageSizeAction -> "ShrinkToFit"],
			RoundingRadius -> 2,
			FrameStyle -> Dynamic[
				If[CurrentValue["MouseOver"], GrayLevel[0.74902], GrayLevel[0, 0]]
			],
			Background -> Dynamic[
				If[CurrentValue["MouseOver"], GrayLevel[0.960784], GrayLevel[1]]
			],
			FrameMargins -> 0,
			ImageMargins -> 0,
			ContentPadding -> False
		],
		(
			AttachCell[
				EvaluationCell[],
				makeChatActionMenu[
					"Delimiter",
					parentCell[EvaluationCell[]],
					EvaluationCell[]
				],
				{Left, Bottom},
				Offset[{0, 0}, {Left, Top}],
				{Left, Top},
				RemovalConditions -> {"EvaluatorQuit", "MouseClickOutside"}
			];
		),
		Appearance -> $suppressButtonAppearance,
		ImageMargins -> 0,
		FrameMargins -> 0,
		ContentPadding -> False
	];

	button
];

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*makeChatActionMenu*)
SetFallthroughError[makeChatActionMenu]

makeChatActionMenu[
	containerType: "Input" | "Delimiter" | "Toolbar",
	targetObj : _CellObject | _NotebookObject,
	(* The cell that will be the parent of the attached cell that contains this
		chat action menu content. *)
	attachedCellParent : _CellObject | Automatic,
    format_ : "Cell"
] := With[{
	closeMenu = ConfirmReplace[attachedCellParent, {
		parent_CellObject -> Function[
			NotebookDelete[Cells[attachedCellParent, AttachedCell -> True]]
		],
		(* NOTE: Capture the parent EvaluationCell[] immediately instead of
			delaying to do it inside closeMenu because closeMenu may be called
			from an attached sub-menu cell (like Advanced Settings), in which
			case EvaluationCell[] is no longer the top-level attached cell menu.
			We want closeMenu to always close the outermost menu. *)
		Automatic -> With[{parent = EvaluationCell[]},
			Function[
				NotebookDelete @ parent
			]
		]
	}]
}, Module[{
	personas = GetPersonasAssociation[],
	actionCallback
},
	(*--------------------------------*)
	(* Process personas list          *)
	(*--------------------------------*)

	RaiseConfirmMatch[personas, <| (_String -> _Association)... |>];

	(* initialize PrivateFrontEndOptions if they aren't already present or somehow broke *)
	If[!MatchQ[CurrentValue[$FrontEnd, {PrivateFrontEndOptions, "InterfaceSettings", "Chatbook", "VisiblePersonas"}], {___String}],
        CurrentValue[
			$FrontEnd,
			{PrivateFrontEndOptions, "InterfaceSettings", "Chatbook", "VisiblePersonas"}
		] = DeleteCases[Keys[personas], Alternatives["Birdnardo", "RawModel", "Wolfie"]]
	];
	If[!MatchQ[CurrentValue[$FrontEnd, {PrivateFrontEndOptions, "InterfaceSettings", "Chatbook", "PersonaFavorites"}], {___String}],
        CurrentValue[
			$FrontEnd,
			{PrivateFrontEndOptions, "InterfaceSettings", "Chatbook", "PersonaFavorites"}
		] = {"CodeAssistant", "CodeWriter", "PlainChat"}
	];

	(* only show visible personas and sort visible personas based on favorites setting *)
	personas = KeyTake[
		personas,
		CurrentValue[$FrontEnd, {PrivateFrontEndOptions, "InterfaceSettings", "Chatbook", "VisiblePersonas"}]
	];
	personas = With[{
		favorites = CurrentValue[
			$FrontEnd,
			{PrivateFrontEndOptions, "InterfaceSettings", "Chatbook", "PersonaFavorites"}
		]
	},
		Association[
			(* favorites appear in the exact order provided in the CurrentValue *)
			KeyTake[personas, favorites],
			KeySort @ KeyTake[personas, Complement[Keys[personas], favorites]]
		]
	];

	(*
		If this menu is being rendered into a Chat-Driven notebook, make the
		'Plain Chat' persona come first.
	*)
	If[
		TrueQ @ CurrentValue[
			ConfirmReplace[targetObj, {
				cell_CellObject :> ParentNotebook[cell],
				nb_NotebookObject :> nb
			}],
			{TaggingRules, "ChatNotebookSettings", "ChatDrivenNotebook"}
		],
		personas = Association[
			KeyTake[
				personas,
				{
					"PlainChat",
					"RawModel",
					"CodeWriter",
					"CodeAssistant"
				}
			],
			personas
		];
	];

	(*--------------------------------*)

	actionCallback = Function[{field, value}, Replace[field, {
		"Persona" :> (
			CurrentValue[
				targetObj,
				{TaggingRules, "ChatNotebookSettings", "LLMEvaluator"}
			] = value;

			closeMenu[];

			(* If we're changing the persona set on a cell, ensure that we are
				not showing the static "ChatInputCellDingbat" that is set
				when a ChatInput is evaluated. *)
			If[Head[targetObj] === CellObject,
				SetOptions[targetObj, CellDingbat -> Inherited];
			];
		),
		"Role" :> (
			CurrentValue[
				targetObj,
				{TaggingRules, "ChatNotebookSettings", "Role"}
			] = value;
			closeMenu[];
		),
		other_ :> (
			ChatbookWarning[
				"Unexpected field set from LLM configuration action menu: `` => ``",
				InputForm[other],
				InputForm[value]
			];
		)
	}]];

	makeChatActionMenuContent[
        targetObj,
		containerType,
		personas,
        format,
		"ActionCallback" -> actionCallback,
		"PersonaValue" -> currentValueOrigin[
			targetObj,
			{TaggingRules, "ChatNotebookSettings", "LLMEvaluator"}
		],
		"ModelValue" -> currentValueOrigin[
			targetObj,
			{TaggingRules, "ChatNotebookSettings", "Model"}
		],
		"RoleValue" -> currentValueOrigin[
			targetObj,
			{TaggingRules, "ChatNotebookSettings", "Role"}
		],
		"ToolCallFrequency" -> targetObj,
		"TemperatureValue" -> Dynamic[
			currentChatSettings[ targetObj, "Temperature" ],
			newValue |-> (
				CurrentValue[
					targetObj,
					{TaggingRules, "ChatNotebookSettings", "Temperature"}
				] = newValue;
			)
		]
	]
]]

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*makeChatActionMenuContent*)
SetFallthroughError[makeChatActionMenuContent]

Options[makeChatActionMenuContent] = {
	"PersonaValue" -> Automatic,
	"ModelValue" -> Automatic,
	"RoleValue" -> Automatic,
	"ToolCallFrequency" -> Automatic,
	"TemperatureValue" -> Automatic,
	"ActionCallback" -> (Null &)
}

makeChatActionMenuContent[
    targetObj_,
	containerType : "Input" | "Delimiter" | "Toolbar",
	personas_?AssociationQ,
    format_,
	OptionsPattern[]
] := With[{
	callback = OptionValue["ActionCallback"]
}, Module[{
	personaValue = OptionValue["PersonaValue"],
	modelValue = OptionValue["ModelValue"],
	roleValue = OptionValue["RoleValue"],
	toolValue = OptionValue["ToolCallFrequency"],
	tempValue = OptionValue["TemperatureValue"],
	advancedSettingsMenu,
	menuLabel,
	menuItems
},

	(*-------------------------------------------------*)
	(* Construct the Advanced Settings submenu content *)
	(*-------------------------------------------------*)

	advancedSettingsMenu = Join[
		{
			"Temperature",
			{
				None,
				makeTemperatureSlider[tempValue],
				None
			}
		},
        {
			"Tool Call Frequency",
			{
				None,
				makeToolCallFrequencySlider[toolValue],
				None
			}
		},
		{"Roles"},
		Map[
			entry |-> ConfirmReplace[entry, {
				{role_?StringQ, icon_} :> {
					alignedMenuIcon[role, roleValue, icon],
					role,
					Hold[callback["Role", role]]
				}
			}],
			{
				{"User", getIcon["ChatIconUser"]},
				{"System", getIcon["RoleSystem"]}
			}
		]
	];

	advancedSettingsMenu = MakeMenu[
		advancedSettingsMenu,
		GrayLevel[0.85],
		200
	];

	(*------------------------------------*)
	(* Construct the popup menu item list *)
	(*------------------------------------*)

	menuItems = Join[
		{"Personas"},
		KeyValueMap[
			{persona, personaSettings} |-> With[{
				icon = getPersonaMenuIcon[personaSettings]
			},
				{
					alignedMenuIcon[persona, personaValue, icon],
					personaDisplayName[persona, personaSettings],
					Hold[callback["Persona", persona];updateDynamics[{"ChatBlock"}]]
				}
			],
			personas
		],
		{
			ConfirmReplace[containerType, {
				"Input" | "Toolbar" -> Nothing,
				"Delimiter" :> Splice[{
					Delimiter,
					{
						alignedMenuIcon[getIcon["ChatBlockSettingsMenuIcon"]],
						"Chat Block Settings\[Ellipsis]",
						"OpenChatBlockSettings"
					}
				}]
			}],
			Delimiter,
			{alignedMenuIcon[getIcon["PersonaOther"]], "Add & Manage Personas\[Ellipsis]", "PersonaManage"},
			{alignedMenuIcon[getIcon["ToolManagerRepository"]], "Add & Manage Tools\[Ellipsis]", "ToolManage"},
			Delimiter,
            <|
                "Label" -> "Models",
                "Type"  -> "Submenu",
                "Icon"  -> alignedMenuIcon @ getIcon[ "ChatBlockSettingsMenuIcon" ],
                "Data"  :> createServiceMenu[ targetObj, ParentCell @ EvaluationCell[ ] ]
            |>,
            <|
                "Label" -> "Advanced Settings",
                "Type"  -> "Submenu",
                "Icon"  -> alignedMenuIcon @ getIcon[ "AdvancedSettings" ],
                "Data"  -> advancedSettingsMenu
            |>
        }
    ];

    Replace[
        format,
        {
            "List"       :> menuItems,
            "Expression" :> makeChatMenuExpression @ menuItems,
            "Cell"       :> makeChatMenuCell[ menuItems, menuMagnification @ targetObj ],
            expr_        :> throwInternalFailure[ makeChatActionMenuContent, expr ]
        }
    ]
]];

(* ::**************************************************************************************************************:: *)
(* ::Subsubsubsection::Closed:: *)
(*makeChatMenuExpression*)
makeChatMenuExpression // beginDefinition;
makeChatMenuExpression[ menuItems_ ] := MakeMenu[ menuItems, GrayLevel[ 0.85 ], $chatMenuWidth ];
makeChatMenuExpression // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsubsection::Closed:: *)
(*makeChatMenuCell*)
makeChatMenuCell // beginDefinition;

makeChatMenuCell[ menuItems_ ] :=
    makeChatMenuCell[ menuItems, CurrentValue[ Magnification ] ];

makeChatMenuCell[ menuItems_, magnification_ ] :=
    Cell[
        BoxData @ ToBoxes @ makeChatMenuExpression @ menuItems,
        "AttachedChatMenu",
        Magnification -> magnification
    ];

makeChatMenuCell // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*getIcon*)
getIcon[ name_ ] := RawBoxes @ TemplateBox[ { }, name ];

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*Model selection submenu*)

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*createServiceMenu*)
createServiceMenu // beginDefinition;

createServiceMenu[ obj_, root_ ] :=
    With[ { model = currentChatSettings[ obj, "Model" ] },
        MakeMenu[
            Join[
                { "Services" },
                (createServiceItem[ obj, model, root, #1 ] &) /@ getAvailableServiceNames[ ]
            ],
            GrayLevel[ 0.85 ],
            140
        ]
    ];

createServiceMenu // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*createServiceItem*)
createServiceItem // beginDefinition;

createServiceItem[ obj_, model_, root_, service_String ] := <|
    "Type"  -> "Submenu",
    "Label" -> service,
    "Icon"  -> serviceIcon[ model, service ],
    "Data"  :> dynamicModelMenu[ obj, root, model, service ]
|>;

createServiceItem // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*serviceIcon*)
serviceIcon // beginDefinition;

serviceIcon[ KeyValuePattern[ "Service" -> service_String ], service_String ] :=
    alignedMenuIcon[ $currentSelectionCheck, serviceIcon @ service ];

serviceIcon[ _String, "OpenAI" ] :=
    alignedMenuIcon[ $currentSelectionCheck, serviceIcon @ "OpenAI" ];

serviceIcon[ _, service_String ] :=
    alignedMenuIcon[ Style[ $currentSelectionCheck, ShowContents -> False ], serviceIcon @ service ];

serviceIcon[ KeyValuePattern[ "Service" -> service_String ] ] :=
    serviceIcon @ service;

serviceIcon[ "OpenAI"       ] := chatbookIcon[ "ServiceIconOpenAI"   , True ];
serviceIcon[ "Anthropic"    ] := chatbookIcon[ "ServiceIconAnthropic", True ];
serviceIcon[ "PaLM"         ] := chatbookIcon[ "ServiceIconPaLM"     , True ];
serviceIcon[ service_String ] := "";

serviceIcon // endDefinition;

$currentSelectionCheck = Style[ "\[Checkmark]", FontColor -> GrayLevel[ 0.25 ] ];

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*dynamicModelMenu*)
dynamicModelMenu // beginDefinition;

dynamicModelMenu[ obj_, root_, model_, service_? modelListCachedQ ] :=
    makeServiceModelMenu[ obj, root, model, service ];

dynamicModelMenu[ obj_, root_, model_, service_ ] :=
    DynamicModule[ { display },
        display = MakeMenu[
            {
                { service },
                {
                    None,
                    Pane[
                        Column @ {
                            Style[ "Getting available models\[Ellipsis]", "ChatMenuLabel" ],
                            ProgressIndicator[ Appearance -> "Percolate" ]
                        },
                        ImageMargins -> 5
                    ],
                    None
                }
            },
            GrayLevel[ 0.85 ],
            200
        ];

        Dynamic[ display, TrackedSymbols :> { display } ],
        Initialization :> Quiet[
            Needs[ "Wolfram`Chatbook`" -> None ];
            display = catchAlways @ makeServiceModelMenu[ obj, root, model, service ]
        ],
        SynchronousInitialization -> False
    ];

dynamicModelMenu // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*makeServiceModelMenu*)
makeServiceModelMenu // beginDefinition;

makeServiceModelMenu[ obj_, root_, currentModel_, service_String ] :=
	makeServiceModelMenu[ obj, root, currentModel, service, getServiceModelList @ service ];

makeServiceModelMenu[ obj_, root_, currentModel_, service_String, models_List ] :=
    MakeMenu[ Join[ { service }, groupMenuModels[ obj, root, currentModel, models ] ], GrayLevel[ 0.85 ], 280 ];

makeServiceModelMenu // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*groupMenuModels*)
groupMenuModels // beginDefinition;

groupMenuModels[ obj_, root_, currentModel_, models_List ] :=
    groupMenuModels[ obj, root, currentModel, GroupBy[ models, modelGroupName ] ];

groupMenuModels[ obj_, root_, currentModel_, models_Association ] /; Length @ models === 1 :=
    modelMenuItem[ obj, root, currentModel ] /@ First @ models;

groupMenuModels[ obj_, root_, currentModel_, models_Association ] :=
    Flatten[ KeyValueMap[ menuModelGroup[ obj, root, currentModel ], models ], 1 ];

groupMenuModels // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*menuModelGroup*)
menuModelGroup // beginDefinition;

menuModelGroup[ obj_, root_, currentModel_ ] :=
    menuModelGroup[ obj, root, currentModel, ## ] &;

menuModelGroup[ obj_, root_, currentModel_, None, models_List ] :=
    modelMenuItem[ obj, root, currentModel ] /@ models;

menuModelGroup[ obj_, root_, currentModel_, "Snapshot Models", models_List ] :=
    If[ TrueQ @ showSnapshotModelsQ[ ],
        Join[ { "Snapshot Models" }, modelMenuItem[ obj, root, currentModel ] /@ models ],
        { }
    ];

menuModelGroup[ obj_, root_, currentModel_, name_String, models_List ] :=
    Join[ { name }, modelMenuItem[ obj, root, currentModel ] /@ models ];

menuModelGroup // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*modelGroupName*)
modelGroupName // beginDefinition;
modelGroupName[ KeyValuePattern[ "FineTuned" -> True ] ] := "Fine Tuned Models";
modelGroupName[ KeyValuePattern[ "Snapshot"  -> True ] ] := "Snapshot Models";
modelGroupName[ _ ] := None;
modelGroupName // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*modelMenuItem*)
modelMenuItem // beginDefinition;

modelMenuItem[ obj_, root_, currentModel_ ] := modelMenuItem[ obj, root, currentModel, #1 ] &;

modelMenuItem[
    obj_,
    root_,
    currentModel_,
    model: KeyValuePattern @ { "Name" -> name_, "Icon" -> icon_, "DisplayName" -> displayName_ }
] := {
    alignedMenuIcon[ modelSelectionCheckmark[ currentModel, name ], icon ],
    displayName,
    Hold[ removeChatMenus @ root; setModel[ obj, model ] ]
};

modelMenuItem // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*modelSelectionCheckmark*)
modelSelectionCheckmark // beginDefinition;
modelSelectionCheckmark[ KeyValuePattern[ "Name" -> model_String ], model_String ] := $currentSelectionCheck;
modelSelectionCheckmark[ model_String, model_String ] := $currentSelectionCheck;
modelSelectionCheckmark[ _, _ ] := Style[ $currentSelectionCheck, ShowContents -> False ];
modelSelectionCheckmark // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*setModel*)
setModel // beginDefinition;

setModel[ obj_, KeyValuePattern @ { "Service" -> service_String, "Name" -> model_String } ] := (
    CurrentValue[ obj, { TaggingRules, "ChatNotebookSettings", "Model" } ] =
        <| "Service" -> service, "Name" -> model |>
);

setModel // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*Chat settings lookup helpers*)

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*absoluteCurrentValue*)
SetFallthroughError[absoluteCurrentValue]

absoluteCurrentValue[cell_, {TaggingRules, "ChatNotebookSettings", key_}] := currentChatSettings[cell, key]
absoluteCurrentValue[cell_, keyPath_] := AbsoluteCurrentValue[cell, keyPath]

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*currentValueOrigin*)
currentValueOrigin // beginDefinition;

(*
	Get the current value and origin of a cell option value.

	This function will return {origin, value}, where `origin` will be one of:

	* "Inline"    -- this value is set inline in the specified CellObject
	* "Inherited" -- this value is inherited from a style setting outside of the
		specified CellObject.
*)
currentValueOrigin[
	targetObj : _CellObject | _NotebookObject,
	keyPath_List
] := Module[{
	value,
	inlineValue
},
	value = absoluteCurrentValue[targetObj, keyPath];

	(* This was causing dynamics to update on every keystroke, so it's disabled for now: *)
	(* inlineValue = nestedLookup[
		Options[targetObj],
		keyPath,
		None
	]; *)
	inlineValue = value;

	Which[
		inlineValue === None,
			{"Inherited", value},
		True,
			{"Inline", inlineValue}
	]
]

currentValueOrigin // endDefinition;

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*getModelsMenuItems*)
getModelsMenuItems[] := Module[{
	items
},
	items = Select[getModelList[], chatModelQ];

	RaiseAssert[MatchQ[items, {___String}]];

	items = Sort[items];

	If[!TrueQ[showSnapshotModelsQ[]],
		items = Select[ items, Not @* snapshotModelQ ];
	];

	items = AssociationMap[standardizeModelData, items];

	RaiseAssert[MatchQ[items, <| (_?StringQ -> _?AssociationQ)... |>]];

	items
]


(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*Menu construction helpers*)

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*alignedMenuIcon*)
SetFallthroughError[alignedMenuIcon]

alignedMenuIcon[possible_, current_, icon_] := alignedMenuIcon[styleListItem[possible, current], icon]
alignedMenuIcon[check_, icon_] := Row[{check, " ", resizeMenuIcon[icon]}]
(* If menu item does not utilize a checkmark, use an invisible one to ensure it is left-aligned with others *)
alignedMenuIcon[icon_] := alignedMenuIcon[Style["\[Checkmark]", ShowContents -> False], icon]

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*resizeMenuIcon*)
resizeMenuIcon[ icon: _Graphics|_Graphics3D ] :=
	Show[ icon, ImageSize -> { 21, 21 } ];

resizeMenuIcon[ icon_ ] := Pane[
	icon,
	ImageSize       -> { 21, 21 },
	ImageSizeAction -> "ShrinkToFit",
	ContentPadding  -> False
];

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*styleListItem*)
SetFallthroughError[styleListItem]

(*
	Style a list item in the ChatInput option value dropdown based on whether
	its value is set inline in the current cell, inherited from some enclosing
	setting, or not the current value.
*)
styleListItem[
	possibleValue_?StringQ,
	currentValue : {"Inline" | "Inherited", _}
] := (
	Replace[currentValue, {
		(* This possible value is the currently selected value. *)
		{"Inline", possibleValue} :>
			"\[Checkmark]",
		(* This possible value is the inherited selected value. *)
		{"Inherited", possibleValue} :>
			Style["\[Checkmark]", FontColor -> GrayLevel[0.75]],
		(* This possible value is not whatever the currently selected value is. *)
		(* Display a hidden checkmark purely so that this
			is offset by the same amount as list items that
			display a visible checkmark. *)
		_ ->
			Style["\[Checkmark]", ShowContents -> False]
	}]
)

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*Persona property lookup helpers*)

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*personaDisplayName*)
SetFallthroughError[personaDisplayName]

personaDisplayName[name_String] := personaDisplayName[name, GetCachedPersonaData[name]]
personaDisplayName[name_String, data_Association] := personaDisplayName[name, data["DisplayName"]]
personaDisplayName[name_String, displayName_String] := displayName
personaDisplayName[name_String, _] := name

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*getPersonaMenuIcon*)
SetFallthroughError[getPersonaMenuIcon];

getPersonaMenuIcon[ name_String ] := getPersonaMenuIcon @ Lookup[ GetPersonasAssociation[ ], name ];
getPersonaMenuIcon[ KeyValuePattern[ "Icon"|"PersonaIcon" -> icon_ ] ] := getPersonaMenuIcon @ icon;
getPersonaMenuIcon[ KeyValuePattern[ "Default" -> icon_ ] ] := getPersonaMenuIcon @ icon;
getPersonaMenuIcon[ _Missing | _Association | None ] := RawBoxes @ TemplateBox[ { }, "PersonaUnknown" ];
getPersonaMenuIcon[ icon_ ] := icon;

(* If "Full" is specified, resolve TemplateBox icons into their literal
   icon data, so that they will render correctly in places where the Chatbook.nb
   stylesheet is not available. *)
getPersonaMenuIcon[ expr_, "Full" ] :=
	Replace[getPersonaMenuIcon[expr], {
		RawBoxes[TemplateBox[{}, iconStyle_?StringQ]] :> (
			chatbookIcon[iconStyle, False]
		),
		icon_ :> icon
	}]

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*getPersonaIcon*)
getPersonaIcon[ expr_ ] := getPersonaMenuIcon[ expr, "Full" ];

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*Model property lookup helpers*)

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*getModelMenuIcon*)
SetFallthroughError[getModelMenuIcon]

getModelMenuIcon[settings_?AssociationQ] := Module[{},
	Replace[Lookup[settings, "Icon", None], {
		None | _Missing -> Style["", ShowContents -> False],
		icon_ :> icon
	}]
]

(* If "Full" is specified, resolve TemplateBox icons into their literal
   icon data, so that they will render correctly in places where the Chatbook.nb
   stylesheet is not available. *)
getModelMenuIcon[settings_?AssociationQ, "Full"] :=
	Replace[getModelMenuIcon[settings], {
		RawBoxes[TemplateBox[{}, iconStyle_?StringQ]] :> (
			chatbookIcon[iconStyle, False]
		),
		icon_ :> icon
	}]

(* ::**************************************************************************************************************:: *)
(* ::Subsection::Closed:: *)
(*Generic Utilities*)

(* ::**************************************************************************************************************:: *)
(* ::Subsubsection::Closed:: *)
(*nestedLookup*)
SetFallthroughError[nestedLookup]
Attributes[nestedLookup] = {HoldRest}

nestedLookup[as:KeyValuePattern[{}], {keys___}, default_] :=
	Replace[
		GeneralUtilities`ToAssociations[as][keys],
		{
			Missing["KeyAbsent", ___] :> default,
			_[keys] :> default
		}
	]

nestedLookup[as_, key:Except[_List], default_] :=
	With[{keys = key},
		If[ ListQ[keys],
			nestedLookup[as, keys, default],
			nestedLookup[as, {keys}, default]
		]
	]

nestedLookup[as_, keys_] := nestedLookup[as, keys, Missing["KeySequenceAbsent", keys]]

(* ::**************************************************************************************************************:: *)
(* ::Section::Closed:: *)
(*Package Footer*)
If[ Wolfram`ChatbookInternal`$BuildingMX,
    Null;
];

(* :!CodeAnalysis::EndBlock:: *)

End[ ];
EndPackage[ ];