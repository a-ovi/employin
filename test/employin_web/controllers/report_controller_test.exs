defmodule EmployinWeb.ReportControllerTest do
  use EmployinWeb.ConnCase, async: true

  test "requires login", %{conn: conn} do
    conn = get(conn, ~p"/reports/export.csv?from=2026-03-09&to=2026-03-15")
    assert redirected_to(conn) == ~p"/login"
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "exports one row per person per day with hours", %{conn: conn, user: user} do
      event_fixture(user, "joined", ~U[2026-03-10 09:00:00Z])
      event_fixture(user, "left", ~U[2026-03-10 17:30:00Z])

      conn = get(conn, ~p"/reports/export.csv?from=2026-03-09&to=2026-03-15&tz=Etc/UTC")

      assert response_content_type(conn, :csv) =~ "text/csv"

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="employin-hours-2026-03-09-to-2026-03-15.csv")
             ]

      assert response(conn, 200) ==
               "Name,Email,Date,Hours\r\nTest User,#{user.email},2026-03-10,8.50\r\n"
    end

    test "rejects bad ranges", %{conn: conn} do
      assert response(get(conn, ~p"/reports/export.csv?from=nope&to=2026-03-15"), 400)
      assert response(get(conn, ~p"/reports/export.csv"), 400)
    end
  end
end
