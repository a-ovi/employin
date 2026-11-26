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
    assert has_element?(lv, "#otp-countdown")
    assert render(lv) =~ "Enter the code we sent to jane@example.com"

    lv |> form("#otp-form", %{otp: "999999x"}) |> render_submit()
    assert render(lv) =~ "invalid or expired code"

    render_submit(form(lv, "#otp-form", %{otp: otp}))
    token = hidden_value(lv, "#otp-form input[name=token]")
    conn = follow_trigger_action(form(lv, "#otp-form", %{otp: otp, token: token}), conn)

    assert "/profile/setup?token=" <> _ = redirected_to(conn)
  end

  test "keeps the OTP step and the resend cooldown across a refresh", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/login")
    lv |> form("#email-form", user: %{email: "jane@example.com"}) |> render_submit()
    path = assert_patch(lv)
    assert "/login?s=" <> _ = path

    assert_email_sent(fn email ->
      [otp] =
        Regex.run(~r/one-time password is: (\d{6})/, email.text_body, capture: :all_but_first)

      send(self(), {:otp, otp})
    end)

    assert_received {:otp, otp}

    # "Refresh": mount a fresh LiveView on the patched URL.
    {:ok, refreshed, html} = live(conn, path)
    assert html =~ "Enter the code we sent to jane@example.com"

    [seconds] =
      Regex.run(~r/data-seconds="(\d+)"/, render(refreshed), capture: :all_but_first)

    assert String.to_integer(seconds) in 110..120

    # The code from the email still works after the refresh.
    render_submit(form(refreshed, "#otp-form", %{otp: otp}))
    token = hidden_value(refreshed, "#otp-form input[name=token]")
    conn = follow_trigger_action(form(refreshed, "#otp-form", %{otp: otp, token: token}), conn)
    assert "/profile/setup?token=" <> _ = redirected_to(conn)
  end

  test "falls back to the email step for an invalid or expired state", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/login?s=garbage")

    assert html =~ "Sign in to your account"
    assert html =~ "Your verification code has expired"
  end

  test "back to email clears the state from the URL", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/login")
    lv |> form("#email-form", user: %{email: "jane@example.com"}) |> render_submit()
    assert_patch(lv)

    lv |> element("button", "Back to email") |> render_click()

    assert_patch(lv, ~p"/login")
    assert render(lv) =~ "Sign in to your account"
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
