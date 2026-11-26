defmodule EmployinWeb.ErrorHTMLTest do
  use EmployinWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html" do
    assert render_to_string(EmployinWeb.ErrorHTML, "404", "html", []) =~ "Page Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(EmployinWeb.ErrorHTML, "500", "html", []) =~ "Server Error"
  end

  test "falls back to the status message for other templates" do
    assert render_to_string(EmployinWeb.ErrorHTML, "403", "html", []) == "Forbidden"
  end
end
