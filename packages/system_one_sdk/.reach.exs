# Enforce the important SystemOneSDK dependency directions. Generated modules and
# data-only response structs intentionally remain outside these layers; this gate
# protects handwritten semantic/runtime boundaries rather than generated shape.
[
  checks: [source_paths: ["lib"]],
  layers: [
    semantic: [
      "SystemOneSDK.Question",
      "SystemOneSDK.Question.Validation",
      "SystemOneSDK.Question.Noul",
      "SystemOneSDK.Question.Choice",
      "SystemOneSDK.Question.Score",
      "SystemOneSDK.Prepared",
      "SystemOneSDK.Answer",
      "SystemOneSDK.Answer.Noul",
      "SystemOneSDK.Answer.Choice",
      "SystemOneSDK.Answer.Score",
      "SystemOneSDK.Response",
      "SystemOneSDK.RequestBudget",
      "SystemOneSDK.ResponseContract",
      "SystemOneSDK.SemanticResponse"
    ],
    orchestration: [
      "SystemOneSDK.Evaluation",
      "SystemOneSDK.Batch",
      "SystemOneSDK.Batch.Lifecycle",
      "SystemOneSDK.OTP.Server",
      "SystemOneSDK.Telemetry"
    ],
    runtime: [
      "SystemOneSDK.Client",
      "SystemOneSDK.SystemOne",
      "SystemOneSDK.RuntimeCapabilities",
      "SystemOneSDK.ProviderProfile",
      "SystemOneSDK.ResultClassifier",
      "SystemOneSDK.TransportResponse",
      "SystemOneSDK.TransportError"
    ]
  ],
  deps: [
    forbidden: [
      {:semantic, :orchestration},
      {:semantic, :runtime},
      {:runtime, :orchestration}
    ]
  ]
]
