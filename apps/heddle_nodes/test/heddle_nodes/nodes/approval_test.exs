defmodule HeddleNodes.Nodes.ApprovalTest do
  use ExUnit.Case, async: true

  alias HeddleNodes.Nodes.Approval

  test "waits for a call with what people see, and a time limit when one is set" do
    context = %{
      "customer" => "Ana",
      "approval_title" => "Refund {{customer}}?",
      "approval_details" => "",
      "approval_wait" => "2",
      "approval_unit" => "hours"
    }

    assert {:wait, %{"call" => true, "approval" => approval, "resume_at" => at}} =
             Approval.handler(context, nil)

    assert approval == %{"title" => "Refund Ana?", "details" => ""}
    {:ok, at, _offset} = DateTime.from_iso8601(at)
    assert_in_delta DateTime.diff(at, DateTime.utc_now()), 7_200, 5
  end

  test "waits with no limit and a title of its own when they are blank" do
    assert {:wait, wait} = Approval.handler(%{}, nil)
    refute Map.has_key?(wait, "resume_at")
    assert wait["approval"]["title"] == "Approve this run?"
  end

  test "refuses a time limit that isn't a number" do
    assert {:error, message} = Approval.handler(%{"approval_wait" => "soon"}, nil)
    assert message =~ "soon"
  end

  test "approves only on a clear yes, wherever the call put it" do
    for yes <- ["approved", "Approve", " yes ", "true", "1"] do
      assert Approval.decision(%{"query_params" => %{"decision" => yes}}) == "approved"
    end

    assert Approval.decision(%{"body" => %{"decision" => "approved"}}) == "approved"

    for no <- [nil, "", "rejected", "nah", 2] do
      assert Approval.decision(%{"body" => %{"decision" => no}}) == "rejected"
    end

    assert Approval.decision(nil) == "rejected"
  end

  test "keeps who decided only from the Approvals page" do
    assert Approval.result(%{"body" => %{"decision" => "yes", "by" => "boss@example.com"}}) ==
             %{"decision" => "approved", "by" => nil, "comment" => nil}

    assert Approval.result(%{
             "decision" => "rejected",
             "by" => "ana@example.com",
             "comment" => "no"
           }) ==
             %{"decision" => "rejected", "by" => "ana@example.com", "comment" => "no"}
  end
end
