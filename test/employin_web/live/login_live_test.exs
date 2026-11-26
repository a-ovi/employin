defmodule EmployinWeb.LoginLiveTest do
  use EmployinWeb.ConnCase, async: true

  import Swoosh.TestAssertions

  test "redirects logged-in users home", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/login")
  end

  test "validates the email", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/login")

    html = lv |> form("#email-form", user: %{email: "nope"}) |> render_submit()

    assert html =~ "invalid email format"
    refute_email_sent()
  end

  test "emails an OTP and accepts it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/login")

    lv |> form("#email-form", user: %{email: "jane@example.com"}) |> render_submit()

    assert_email_sent(fn email ->
      assert email.to == [{"", "jane@example.com"}]
      assert email.text_body =~ "/login/verify?token="

      [otp] =
        Regex.run(~r/one-time password is: (\d{6})/, email.text_body, capture: :all_but_first)

      send(self(), {:otp, otp})
    end)

    assert_received {:otp, otp}
    assert has_element?(lv, "#otp-countdown[data-seconds='120']")

    lv |> form("#otp-form", %{otp: "999999x"}) |> render_submit()
    assert render(lv) =~ "invalid or expired code"

    render_submit(form(lv, "#otp-form", %{otp: otp}))
    token = hidden_value(lv, "#otp-form input[name=token]")
    conn = follow_trigger_action(form(lv, "#otp-form", %{otp: otp, token: token}), conn)

    assert "/profile/setup?token=" <> _ = redirected_to(conn)
  end

  test "throttles resending the OTP", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/login")
    lv |> form("#email-form", user: %{email: "jane@example.com"}) |> render_submit()
    assert_email_sent()

    # Fake a finished client-side countdown; the server still enforces the cooldown.
    render_hook(lv, "countdown-finished", %{})
    lv |> element("#resend-button") |> render_click()

    assert render(lv) =~ "Please wait before requesting a new code."
    refute_email_sent()
  end
end
