defmodule EmployinWeb.RegistrationLiveTest do
  use EmployinWeb.ConnCase, async: true

  alias Employin.LoginToken
  alias Employin.Users

  test "requires a registration token", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/profile/setup")

    token = LoginToken.sign(:session, "x@example.com")
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/profile/setup?token=#{token}")
  end

  test "creates the user and logs them in", %{conn: conn} do
    token = LoginToken.sign(:registration, "new@example.com")
    {:ok, lv, html} = live(conn, ~p"/profile/setup?token=#{token}")
    assert html =~ "new@example.com"

    assert lv |> form("#registration-form", user: %{display_name: "Al"}) |> render_change() =~
             "should be at least 5 character(s)"

    lv |> form("#registration-form", user: %{display_name: "New Person"}) |> render_submit()
    token = hidden_value(lv, "#registration-form input[name=token]")
    form = form(lv, "#registration-form", user: %{display_name: "New Person"}, token: token)
    conn = follow_trigger_action(form, conn)

    assert redirected_to(conn) == ~p"/"
    assert %{display_name: "New Person"} = Users.get_by_email("new@example.com")
  end
end
