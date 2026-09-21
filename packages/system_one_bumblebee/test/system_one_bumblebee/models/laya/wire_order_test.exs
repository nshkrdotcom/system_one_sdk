defmodule SystemOneBumblebee.Models.Laya.WireOrderTest do
  use ExUnit.Case,
    async: true

  alias SystemOneBumblebee.Models.Laya.Preprocessing

  test "raw ordered question objects preserve Choice order" do
    question =
      Jason.OrderedObject.new([
        {"type", "choice"},
        {"instructions", "Choose one."},
        {"criteria",
         Jason.OrderedObject.new([
           {"zeta", "first"},
           {"alpha", "second"}
         ])}
      ])

    assert {:ok, normalized} =
             Preprocessing.normalize_question(question)

    assert normalized.type ==
             "choice"

    assert normalized.criteria ==
             [
               {"zeta", "first"},
               {"alpha", "second"}
             ]

    assert {:ok,
            [
              "zeta: first",
              "alpha: second"
            ]} =
             Preprocessing.render_options(question)
  end
end
