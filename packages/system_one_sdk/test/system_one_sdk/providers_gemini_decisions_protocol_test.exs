defmodule SystemOneSDK.Providers.GeminiDecisionsProtocolTest do
  use ExUnit.Case, async: true

  alias SystemOneSDK.Answer.Choice
  alias SystemOneSDK.{Error, Prepared, SemanticResponse}
  alias SystemOneSDK.Providers.GeminiDecisions.Protocol

  defp prep_noul do
    Prepared.new!(is_spam: SystemOneSDK.noul("Does this message contain unsolicited spam?"))
  end

  defp prep_criteria_noul do
    Prepared.new!(
      criteria_spam:
        SystemOneSDK.noul("Is this spam?",
          true: "Unsolicited promotional message.",
          false: "Expected conversation."
        )
    )
  end

  defp prep_choice do
    Prepared.new!(
      tone:
        SystemOneSDK.choice(
          "Classify the overall tone of the message.",
          positive: "Constructive, appreciative, or favorable tone.",
          negative: "Critical, frustrated, or dissatisfied tone."
        )
    )
  end

  defp prep_score do
    Prepared.new!(
      completeness:
        SystemOneSDK.score(
          "Rate how complete the submission is.",
          [
            {"incomplete", "Missing required fields."},
            {"partial", "Some fields are populated."},
            {"complete", "All required fields are populated."}
          ]
        )
    )
  end

  defp prep_numeric_score do
    Prepared.new!(
      numeric_rating:
        SystemOneSDK.score(
          "Rate 1 to 3.",
          [{"1", "Poor"}, {"2", "Okay"}, {"3", "Great"}]
        )
    )
  end

  defp prep_triage do
    Prepared.new!(
      urgent: SystemOneSDK.noul("Is this urgent?"),
      priority: SystemOneSDK.choice("Select priority.", p0: "Outage", p2: "Routine"),
      clarity:
        SystemOneSDK.score(
          "Rate clarity.",
          [{"vague", "Unclear"}, {"partial", "Partial"}, {"clear", "Clear"}]
        )
    )
  end

  describe "request payload encoding" do
    test "encodes unified /v1/decisions payload for noul, choice, score, and multi-question contracts" do
      prep = prep_triage()

      payload =
        Protocol.encode_request(%{body: "502 on checkout"}, prep, "gemini-decision-1", :unified)

      assert payload["model"] == "gemini-decision-1"
      assert is_binary(payload["input"])
      assert Jason.decode!(payload["input"]) == %{"body" => "502 on checkout"}

      assert [
               %{"type" => "predicate", "name" => "urgent", "instructions" => "Is this urgent?"},
               %{
                 "type" => "choice",
                 "name" => "priority",
                 "instructions" => "Select priority.",
                 "choices" => [
                   %{"value" => "p0", "description" => "Outage"},
                   %{"value" => "p2", "description" => "Routine"}
                 ]
               },
               %{
                 "type" => "score",
                 "name" => "clarity",
                 "instructions" => "Rate clarity.",
                 "levels" => [
                   %{"label" => "vague", "description" => "Unclear"},
                   %{"label" => "partial", "description" => "Partial"},
                   %{"label" => "clear", "description" => "Clear"}
                 ]
               }
             ] = payload["questions"]
    end

    test "preserves non-alphabetical choice declaration order in unified /v1/decisions payloads" do
      prep = prep_choice()
      assert prep.definitions["tone"].option_order == [:positive, :negative]

      payload = Protocol.encode_request(%{body: "Great job!"}, prep, "gemini-decision-1", :unified)

      assert [
               %{
                 "type" => "choice",
                 "name" => "tone",
                 "choices" => [
                   %{"value" => "positive", "description" => _},
                   %{"value" => "negative", "description" => _}
                 ]
               }
             ] = payload["questions"]

      map_criteria_prep =
        put_in(prep.definitions["tone"].criteria, %{
          negative: "Critical, frustrated, or dissatisfied tone.",
          positive: "Constructive, appreciative, or favorable tone."
        })

      map_payload =
        Protocol.encode_request(
          %{body: "Great job!"},
          map_criteria_prep,
          "gemini-decision-1",
          :unified
        )

      assert [
               %{
                 "choices" => [
                   %{"value" => "positive"},
                   %{"value" => "negative"}
                 ]
               }
             ] = map_payload["questions"]
    end

    test "encodes native /v1beta/decisions payload with map-keyed questions" do
      prep = prep_triage()
      payload = Protocol.encode_request("raw input text", prep, "gemini-decision-1", :native)

      assert payload["model"] == "gemini-decision-1"
      assert payload["input"] == "raw input text"

      assert %{
               "urgent" => %{"type" => "noul", "instructions" => "Is this urgent?"},
               "priority" => %{
                 "type" => "choice",
                 "instructions" => "Select priority.",
                 "criteria" => %{"p0" => "Outage", "p2" => "Routine"}
               },
               "clarity" => %{
                 "type" => "score",
                 "instructions" => "Rate clarity.",
                 "criteria" => ["Unclear", "Partial", "Clear"]
               }
             } = payload["questions"]
    end

    test "folds noul true/false criteria into instructions without emitting a criteria key" do
      prep = prep_criteria_noul()

      unified_payload =
        Protocol.encode_request(%{body: "Buy now!"}, prep, "gemini-decision-1", :unified)

      assert [q_uni] = unified_payload["questions"]
      assert q_uni["type"] == "predicate"
      assert q_uni["name"] == "criteria_spam"
      assert q_uni["instructions"] =~ "Is this spam?"
      assert q_uni["instructions"] =~ "true: Unsolicited promotional message."
      assert q_uni["instructions"] =~ "false: Expected conversation."
      refute Map.has_key?(q_uni, "criteria")

      native_payload =
        Protocol.encode_request(%{body: "Buy now!"}, prep, "gemini-decision-1", :native)

      assert %{"criteria_spam" => q_nat} = native_payload["questions"]
      assert q_nat["type"] == "noul"
      assert q_nat["instructions"] =~ "Is this spam?"
      assert q_nat["instructions"] =~ "true: Unsolicited promotional message."
      assert q_nat["instructions"] =~ "false: Expected conversation."
      refute Map.has_key?(q_nat, "criteria")
    end

    test "builds auth headers for Bearer (unified), x-goog-api-key (native), and :none" do
      assert Protocol.auth_headers("secret-1", :bearer) == %{
               "Authorization" => "Bearer secret-1"
             }

      assert Protocol.auth_headers("secret-2", :x_goog_api_key) == %{
               "x-goog-api-key" => "secret-2"
             }

      assert Protocol.auth_headers("secret-3", :none) == %{}
    end
  end

  describe "response decoding and normalization" do
    test "decodes unified /v1/decisions multi-question response and enriches via SemanticResponse" do
      prep = prep_triage()

      body = %{
        "model" => "gemini/gemini-decision-1",
        "answers" => [
          %{"name" => "urgent", "type" => "predicate", "probability" => 0.99},
          %{
            "name" => "priority",
            "type" => "choice",
            "choice" => "p0",
            "confidence" => 0.95,
            "probabilities" => [
              %{"value" => "p0", "probability" => 0.95},
              %{"value" => "p2", "probability" => 0.05}
            ]
          },
          %{
            "name" => "clarity",
            "type" => "score",
            "score" => 1.82,
            "confidence" => 0.91,
            "probabilities" => [
              %{"value" => 0, "label" => "vague", "probability" => 0.02},
              %{"value" => 1, "label" => "partial", "probability" => 0.07},
              %{"value" => 2, "label" => "clear", "probability" => 0.91}
            ]
          }
        ],
        "usage" => %{"input_tokens" => 93, "output_tokens" => 0}
      }

      assert {:ok, resp} = Protocol.decode_response(body, prep, "gemini-decision-1")
      assert resp.model == "gemini/gemini-decision-1"
      assert resp.usage.input_tokens == 93
      assert resp.usage.output_tokens == 0
      assert {:ok, enriched} = SemanticResponse.enrich(resp, prep, 0.02)
      assert enriched.answers.urgent.noul == 0.99
      assert enriched.answers.priority.choice == :p0
      assert enriched.answers.priority.probabilities == %{p0: 0.95, p2: 0.05}
      assert enriched.answers.clarity.level == 2
      assert enriched.answers.clarity.label == "clear"
    end

    test "decodes native /v1beta/decisions map-keyed response and camelCase usageMetadata" do
      prep = prep_triage()

      body = %{
        "answers" => %{
          "urgent" => %{"noul" => 0.98, "confidence" => 0.98},
          "priority" => %{
            "choice" => "p2",
            "confidence" => 0.55,
            "probabilities" => %{"p0" => 0.45, "p2" => 0.55}
          },
          "clarity" => %{
            "score" => 1.66,
            "confidence" => 0.72,
            "probabilities" => %{"0" => 0.06, "1" => 0.22, "2" => 0.72}
          }
        },
        "usageMetadata" => %{"totalInputTokens" => 94, "totalOutputTokens" => 7}
      }

      assert {:ok, resp} = Protocol.decode_response(body, prep, "gemini-decision-1")
      assert resp.model == "gemini-decision-1"
      assert resp.usage.input_tokens == 94
      assert resp.usage.output_tokens == 7
      assert {:ok, enriched} = SemanticResponse.enrich(resp, prep, 0.02)
      assert enriched.answers.priority.choice == :p2
      assert enriched.answers.clarity.level == 2
    end

    test "decodes single-question flat confidence/probability and boolean noul polarity" do
      prep = prep_noul()

      assert {:ok, flat_resp} =
               Protocol.decode_response(
                 %{"confidence" => 0.97977, "total_input_tokens" => 94, "total_output_tokens" => 0},
                 prep,
                 "gemini-decision-1"
               )

      assert flat_resp.answers["is_spam"].noul == 0.97977
      assert flat_resp.usage.input_tokens == 94

      assert {:ok, false_resp} =
               Protocol.decode_response(
                 %{"noul" => false, "confidence" => 0.98},
                 prep,
                 "gemini-decision-1"
               )

      assert_in_delta false_resp.answers["is_spam"].noul, 0.02, 1.0e-6

      assert {:error,
              %Error{
                type: :response_validation,
                details: %{reason: :contradictory_noul_polarity}
              }} =
               Protocol.decode_response(
                 %{"decision" => false, "probability" => 0.95},
                 prep,
                 "gemini-decision-1"
               )
    end

    test "backfills choice probabilities without flipping winner and normalizes score scales" do
      two_prep = prep_choice()
      score_prep = prep_score()
      num_prep = prep_numeric_score()

      assert {:ok, resp2} =
               Protocol.decode_response(
                 %{"choice" => "positive", "confidence" => 0.40},
                 two_prep,
                 "gemini-decision-1"
               )

      assert {:ok, enriched2} = SemanticResponse.enrich(resp2, two_prep, 0.02)
      assert Choice.margin(enriched2.answers.tone) == 0.0

      assert {:ok, norm_resp} =
               Protocol.decode_response(
                 %{
                   "answers" => %{
                     "completeness" => %{
                       "type" => "score",
                       "score" => 0.925,
                       "confidence" => 0.9,
                       "probabilities" => %{"0" => 0.05, "1" => 0.05, "2" => 0.90}
                     }
                   }
                 },
                 score_prep,
                 "gemini-decision-1"
               )

      assert_in_delta norm_resp.answers["completeness"].score, 1.85, 1.0e-6

      assert {:ok, num_lbl_resp} =
               Protocol.decode_response(
                 %{
                   "answers" => %{
                     "numeric_rating" => %{
                       "score" => 1.80,
                       "confidence" => 0.85,
                       "probabilities" => %{"1" => 0.05, "2" => 0.10, "3" => 0.85}
                     }
                   }
                 },
                 num_prep,
                 "gemini-decision-1"
               )

      assert num_lbl_resp.answers["numeric_rating"].probabilities == %{
               0 => 0.05,
               1 => 0.10,
               2 => 0.85
             }
    end

    test "returns structured SystemOneSDK.Error values for invalid payloads and unencodable state" do
      noul_prep = prep_noul()
      choice_prep = prep_choice()
      score_prep = prep_score()

      assert {:error, %Error{type: :invalid_request}} =
               Protocol.encode_request_safe(
                 %{pid: self()},
                 noul_prep,
                 "gemini-decision-1",
                 :unified
               )

      assert {:error, %Error{type: :invalid_request}} =
               Protocol.encode_request_safe(<<255, 255>>, noul_prep, "gemini-decision-1", :native)

      assert {:error, %Error{type: :response_validation}} =
               Protocol.decode_response("not a map", noul_prep, "gemini-decision-1")

      assert {:error, %Error{type: :api_error}} =
               Protocol.decode_response(
                 %{"error" => %{"message" => "Rate limit"}, "value" => 0.0},
                 noul_prep,
                 "gemini-decision-1"
               )

      assert {:error, %Error{type: :response_validation}} =
               Protocol.decode_response(
                 %{"choice" => "hallucinated", "confidence" => 0.95},
                 choice_prep,
                 "gemini-decision-1"
               )

      assert {:error, %Error{type: :response_validation, details: %{reason: :score_out_of_range}}} =
               Protocol.decode_response(
                 %{"score" => 2.5, "confidence" => 0.9},
                 score_prep,
                 "gemini-decision-1"
               )
    end

    test "computes expected score when probabilities are present and score is omitted" do
      score_prep = prep_score()

      assert {:ok, resp} =
               Protocol.decode_response(
                 %{"probabilities" => %{"0" => 0.05, "1" => 0.05, "2" => 0.90}},
                 score_prep,
                 "gemini-decision-1"
               )

      assert_in_delta resp.answers["completeness"].score, 1.85, 1.0e-6
      assert resp.answers["completeness"].confidence == 0.90
      assert {:ok, enriched} = SemanticResponse.enrich(resp, score_prep, 0.02)
      assert enriched.answers.completeness.level == 2
      assert enriched.answers.completeness.label == "complete"

      assert {:ok, rounded_resp} =
               Protocol.decode_response(
                 %{
                   "answers" => %{
                     "completeness" => %{
                       "probabilities" => %{"0" => 0.0, "1" => 0.0, "2" => 0.99}
                     }
                   }
                 },
                 score_prep,
                 "gemini-decision-1"
               )

      assert_in_delta rounded_resp.answers["completeness"].score, 2.0, 1.0e-6

      assert {:ok, proto3_zero_resp} =
               Protocol.decode_response(
                 %{"type" => "score", "confidence" => 0.95},
                 score_prep,
                 "gemini-decision-1"
               )

      assert proto3_zero_resp.answers["completeness"].score == 0.0
    end

    test "backfills choice probabilities symmetrically for 3+ options when 1/n <= confidence < 0.5" do
      four_prep =
        Prepared.new!(
          bucket:
            SystemOneSDK.choice("Pick bucket.",
              a: "Bucket A",
              b: "Bucket B",
              c: "Bucket C",
              d: "Bucket D"
            )
        )

      assert {:ok, resp} =
               Protocol.decode_response(
                 %{"choice" => "a", "confidence" => 0.40},
                 four_prep,
                 "gemini-decision-1"
               )

      probs = resp.answers["bucket"].probabilities
      assert_in_delta probs["a"], 0.40, 1.0e-6
      assert_in_delta probs["b"], 0.20, 1.0e-6
      assert_in_delta probs["c"], 0.20, 1.0e-6
      assert_in_delta probs["d"], 0.20, 1.0e-6

      assert {:ok, enriched} = SemanticResponse.enrich(resp, four_prep, 0.02)
      assert_in_delta Choice.margin(enriched.answers.bucket), 0.20, 1.0e-6
    end

    test "rescales low normalized scores continuously and resolves partial/reordered numeric labels" do
      score_prep = prep_score()
      num_prep = prep_numeric_score()

      reordered_prep =
        Prepared.new!(
          rev_rating:
            SystemOneSDK.score(
              "Rate 2 down to 0.",
              [{"2", "Two"}, {"1", "One"}, {"0", "Zero"}]
            )
        )

      assert {:ok, low_scaled} =
               Protocol.decode_response(
                 %{
                   "answers" => %{
                     "completeness" => %{
                       "type" => "score",
                       "score" => 0.10,
                       "confidence" => 0.80,
                       "probabilities" => %{"0" => 0.80, "1" => 0.20, "2" => 0.0}
                     }
                   }
                 },
                 score_prep,
                 "gemini-decision-1"
               )

      assert_in_delta low_scaled.answers["completeness"].score, 0.20, 1.0e-6

      assert {:ok, low_unscaled} =
               Protocol.decode_response(
                 %{
                   "answers" => %{
                     "completeness" => %{
                       "type" => "score",
                       "score" => 0.10,
                       "confidence" => 0.90,
                       "probabilities" => %{"0" => 0.90, "1" => 0.10, "2" => 0.0}
                     }
                   }
                 },
                 score_prep,
                 "gemini-decision-1"
               )

      assert_in_delta low_unscaled.answers["completeness"].score, 0.10, 1.0e-6

      assert {:ok, partial_num} =
               Protocol.decode_response(
                 %{
                   "answers" => %{
                     "numeric_rating" => %{
                       "score" => 0.80,
                       "confidence" => 0.80,
                       "probabilities" => %{"1" => 0.20, "2" => 0.80}
                     }
                   }
                 },
                 num_prep,
                 "gemini-decision-1"
               )

      assert partial_num.answers["numeric_rating"].probabilities == %{0 => 0.20, 1 => 0.80}

      assert {:ok, rev_num} =
               Protocol.decode_response(
                 %{
                   "answers" => %{
                     "rev_rating" => %{
                       "score" => 1.60,
                       "confidence" => 0.70,
                       "probabilities" => %{"2" => 0.10, "1" => 0.20, "0" => 0.70}
                     }
                   }
                 },
                 reordered_prep,
                 "gemini-decision-1"
               )

      assert rev_num.answers["rev_rating"].probabilities == %{0 => 0.10, 1 => 0.20, 2 => 0.70}
    end

    test "handles confidence-only noul consistently, rejects contradictory < 0.5 confidence, surfaces errors, and rejects duplicates" do
      noul_prep = prep_noul()
      choice_prep = prep_choice()

      for payload <- [
            %{"confidence" => 0.98},
            %{"type" => "noul", "confidence" => 0.98},
            %{"answers" => %{"is_spam" => %{"confidence" => 0.98}}},
            %{"answers" => [%{"name" => "is_spam", "type" => "predicate", "confidence" => 0.98}]}
          ] do
        assert {:ok, resp} = Protocol.decode_response(payload, noul_prep, "gemini-decision-1")
        assert resp.answers["is_spam"].noul == 0.98
      end

      assert {:error,
              %Error{
                type: :response_validation,
                details: %{reason: :contradictory_noul_polarity}
              }} =
               Protocol.decode_response(
                 %{"decision" => false, "confidence" => 0.10},
                 noul_prep,
                 "gemini-decision-1"
               )

      assert {:error,
              %Error{
                type: :response_validation,
                details: %{reason: :contradictory_noul_polarity}
              }} =
               Protocol.decode_response(
                 %{"decision" => false, "confidence" => 0.90, "probability" => 0.90},
                 noul_prep,
                 "gemini-decision-1"
               )

      assert {:ok, value_resp} =
               Protocol.decode_response(
                 %{"decision" => false, "value" => 0.15},
                 noul_prep,
                 "gemini-decision-1"
               )

      assert value_resp.answers["is_spam"].noul == 0.15

      for err_payload <- [
            %{"answers" => [], "error" => %{"message" => "Quota exceeded"}},
            %{"answers" => %{}, "error" => %{"message" => "Quota exceeded"}}
          ] do
        assert {:error, %Error{type: :api_error}} =
                 Protocol.decode_response(err_payload, noul_prep, "gemini-decision-1")
      end

      assert {:error,
              %Error{
                type: :response_validation,
                details: %{reason: :duplicate_answer_entry}
              }} =
               Protocol.decode_response(
                 %{
                   "answers" => [
                     %{"name" => "is_spam", "probability" => 0.9},
                     %{"name" => "is_spam", "probability" => 0.1}
                   ]
                 },
                 noul_prep,
                 "gemini-decision-1"
               )

      assert {:error,
              %Error{
                type: :response_validation,
                details: %{reason: :invalid_probabilities}
              }} =
               Protocol.decode_response(
                 %{
                   "choice" => "positive",
                   "confidence" => 0.8,
                   "probabilities" => [
                     %{"value" => "positive", "probability" => 0.8},
                     %{"value" => "positive", "probability" => 0.2}
                   ]
                 },
                 choice_prep,
                 "gemini-decision-1"
               )

      assert {:error,
              %Error{
                type: :response_validation,
                details: %{reason: :invalid_probabilities}
              }} =
               Protocol.decode_response(
                 %{
                   "choice" => "positive",
                   "confidence" => 0.8,
                   "probabilities" => %{"positive" => 0.8, "unknown_opt" => 0.2}
                 },
                 choice_prep,
                 "gemini-decision-1"
               )
    end

    test "resolves sparse 0-based index maps and explicit stringified index fields under numeric labels" do
      num_prep = prep_numeric_score()

      assert {:ok, sparse_idx_resp} =
               Protocol.decode_response(
                 %{
                   "answers" => %{
                     "numeric_rating" => %{
                       "score" => 1.60,
                       "confidence" => 0.80,
                       "probabilities" => %{"0" => 0.20, "2" => 0.80}
                     }
                   }
                 },
                 num_prep,
                 "gemini-decision-1"
               )

      assert sparse_idx_resp.answers["numeric_rating"].probabilities == %{0 => 0.20, 2 => 0.80}

      assert {:ok, list_idx_resp} =
               Protocol.decode_response(
                 %{
                   "answers" => %{
                     "numeric_rating" => %{
                       "probabilities" => [
                         %{"index" => "0", "probability" => 0.30},
                         %{"index" => "1", "probability" => 0.70}
                       ]
                     }
                   }
                 },
                 num_prep,
                 "gemini-decision-1"
               )

      assert list_idx_resp.answers["numeric_rating"].probabilities == %{0 => 0.30, 1 => 0.70}

      assert {:ok, single_idx_resp} =
               Protocol.decode_response(
                 %{
                   "answers" => %{
                     "numeric_rating" => %{
                       "probabilities" => [%{"index" => "1", "probability" => 0.70}]
                     }
                   }
                 },
                 num_prep,
                 "gemini-decision-1"
               )

      assert single_idx_resp.answers["numeric_rating"].probabilities == %{1 => 0.70}
    end

    test "rejects top-level structs and struct answer entries with :response_validation" do
      noul_prep = prep_noul()

      assert {:error, %Error{type: :response_validation}} =
               Protocol.decode_response(%URI{}, noul_prep, "gemini-decision-1")

      assert {:error, %Error{type: :response_validation}} =
               Protocol.decode_response(
                 %{"answers" => %{"is_spam" => ~D[2026-01-01]}},
                 noul_prep,
                 "gemini-decision-1"
               )
    end
  end
end
