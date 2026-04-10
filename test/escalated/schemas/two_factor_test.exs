defmodule Escalated.Schemas.TwoFactorTest do
  use ExUnit.Case, async: true
  alias Escalated.Schemas.TwoFactor

  test "use_recovery_code removes valid code" do
    tf = %TwoFactor{recovery_codes: ["code-1", "code-2", "code-3"]}
    {result, codes} = TwoFactor.use_recovery_code(tf, "code-2")

    assert result == true
    assert length(codes) == 2
    refute "code-2" in codes
  end

  test "use_recovery_code rejects invalid code" do
    tf = %TwoFactor{recovery_codes: ["code-1"]}
    {result, codes} = TwoFactor.use_recovery_code(tf, "invalid")

    assert result == false
    assert codes == ["code-1"]
  end

  test "use_recovery_code with nil codes" do
    tf = %TwoFactor{recovery_codes: nil}
    {result, codes} = TwoFactor.use_recovery_code(tf, "code")

    assert result == false
    assert codes == nil
  end
end
